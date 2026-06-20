using FCGames.IntegrationEvents;
using Fiap.FCGames.Payments.Domain.Aggregates.AggregatePagamento;
using Fiap.FCGames.Payments.Domain.Enums;
using Fiap.FCGames.Payments.Infra.DataProvider.Interface;
using MassTransit;
using Microsoft.Extensions.Logging;

namespace Fiap.FCGames.Payments.Worker.Consumers;

public class PedidoRealizadoEventoConsumer : IConsumer<PedidoRealizadoEvento>
{
    private readonly IUnitOfWork _uow;
    private readonly IPublishEndpoint _publishEndpoint;
    private readonly ILogger<PedidoRealizadoEventoConsumer> _logger;

    public PedidoRealizadoEventoConsumer(
        IUnitOfWork uow,
        IPublishEndpoint publishEndpoint,
        ILogger<PedidoRealizadoEventoConsumer> logger)
    {
        _uow = uow;
        _publishEndpoint = publishEndpoint;
        _logger = logger;
    }

    public async Task Consume(ConsumeContext<PedidoRealizadoEvento> context)
    {
        var evt = context.Message;

        var existente = await _uow.PagamentoRepository.ObterPorPedidoIdAsync(evt.PedidoId);
        if (existente is not null)
        {
            _logger.LogInformation("PedidoId {PedidoId} já processado — idempotente", evt.PedidoId);
            return;
        }

        var (status, motivo) = AplicarRegra(evt.Preco);

        var pagamento = new Pagamento
        {
            Id = Guid.NewGuid(),
            PedidoId = evt.PedidoId,
            UsuarioId = evt.UsuarioId,
            JogoId = evt.JogoId,
            Valor = evt.Preco,
            Status = status,
            Motivo = motivo,
            ProcessadoEm = DateTime.UtcNow
        };

        _uow.PagamentoRepository.Adicionar(pagamento);

        await _publishEndpoint.Publish(new PagamentoProcessadoEvento(
            evt.PedidoId,
            evt.UsuarioId,
            evt.JogoId,
            evt.NomeJogo,
            evt.Preco,
            status.ToString(),
            motivo,
            DateTime.UtcNow,
            evt.CorrelationId),
            context.CancellationToken);

        await _uow.CommitAsync(context.CancellationToken);

        _logger.LogInformation(
            "Pagamento {PedidoId} processado: {Status}. Motivo: {Motivo}",
            evt.PedidoId, status.ToString(), motivo ?? "N/A");
    }

    private static (StatusPagamento status, string? motivo) AplicarRegra(decimal preco)
    {
        if (preco <= 0)
            return (StatusPagamento.Rejeitado, "Valor inválido");
        if (preco > 100)
            return (StatusPagamento.Rejeitado, "Limite de crédito excedido");
        return (StatusPagamento.Aprovado, null);
    }
}
