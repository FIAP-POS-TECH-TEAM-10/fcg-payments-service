using MediatR;

namespace Fiap.FCGames.Payments.Application.Queries.BuscarPagamento;

public record BuscarPagamentoQuery(Guid OrderId) : IRequest<BuscarPagamentoResponse?>;
