using Fiap.FCGames.Payments.Domain.Enums;

namespace Fiap.FCGames.Payments.Domain.Aggregates.AggregatePagamento;

public class Pagamento
{
    public Guid Id { get; set; }
    public Guid PedidoId { get; set; }
    public Guid UsuarioId { get; set; }
    public Guid JogoId { get; set; }
    public decimal Valor { get; set; }
    public StatusPagamento Status { get; set; }
    public string? Motivo { get; set; }
    public DateTime ProcessadoEm { get; set; }
}
