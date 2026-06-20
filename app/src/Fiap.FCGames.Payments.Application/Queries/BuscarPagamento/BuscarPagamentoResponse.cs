namespace Fiap.FCGames.Payments.Application.Queries.BuscarPagamento;

public record BuscarPagamentoResponse(
    Guid OrderId,
    decimal Valor,
    string Status,
    string? Motivo,
    DateTime ProcessadoEm);
