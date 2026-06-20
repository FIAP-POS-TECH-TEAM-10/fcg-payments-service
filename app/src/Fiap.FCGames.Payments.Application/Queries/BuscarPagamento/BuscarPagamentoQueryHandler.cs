using Fiap.FCGames.Payments.Infra.DataProvider.Interface;
using MediatR;

namespace Fiap.FCGames.Payments.Application.Queries.BuscarPagamento;

public class BuscarPagamentoQueryHandler : IRequestHandler<BuscarPagamentoQuery, BuscarPagamentoResponse?>
{
    private readonly IUnitOfWork _uow;

    public BuscarPagamentoQueryHandler(IUnitOfWork uow) => _uow = uow;

    public async Task<BuscarPagamentoResponse?> Handle(BuscarPagamentoQuery request, CancellationToken cancellationToken)
    {
        var pagamento = await _uow.PagamentoRepository.ObterPorPedidoIdAsync(request.OrderId);
        if (pagamento is null) return null;

        return new BuscarPagamentoResponse(
            pagamento.PedidoId,
            pagamento.Valor,
            pagamento.Status.ToString(),
            pagamento.Motivo,
            pagamento.ProcessadoEm);
    }
}
