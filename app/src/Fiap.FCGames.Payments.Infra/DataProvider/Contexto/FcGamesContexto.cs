using Microsoft.EntityFrameworkCore;

namespace Fiap.FCGames.Payments.Infra.DataProvider.Contexto;

public class FcGamesContexto : DbContext
{
    public FcGamesContexto(DbContextOptions<FcGamesContexto> options) : base(options) { }

    // TODO: adicionar DbSets do domínio Pagamentos:
    // public DbSet<Pagamento> Pagamentos { get; set; }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        // TODO: aplicar configurações das entidades do domínio Pagamentos
    }
}
