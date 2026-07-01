using Fiap.FCGames.Payments.CrossCutting.Extensions;
using Fiap.FCGames.Payments.Infra.DataProvider.Contexto;
using Fiap.FCGames.Payments.Worker.Consumers;
using MassTransit;
using Microsoft.EntityFrameworkCore;
using Serilog;

var builder = Host.CreateApplicationBuilder(args);

Log.Logger = new LoggerConfiguration()
    .ReadFrom.Configuration(builder.Configuration)
    .Enrich.FromLogContext()
    .CreateLogger();

builder.Logging.ClearProviders();
builder.Services.AddSerilog();

builder.Services.RegisterDI();
builder.Services.AddContextDatabase(builder.Configuration);

builder.Services.AddMassTransit(x =>
{
    x.AddConsumer<PedidoRealizadoEventoConsumer>();

    x.AddEntityFrameworkOutbox<FcGamesContexto>(o =>
    {
        o.UseSqlite();
    });

    x.UsingRabbitMq((ctx, cfg) =>
    {
        var rabbitHost = builder.Configuration["RabbitMQ:Host"] ?? "localhost";
        var username = builder.Configuration["RabbitMQ:Username"] ?? "guest";
        var password = builder.Configuration["RabbitMQ:Password"] ?? "guest";

        cfg.Host(rabbitHost, "/", h =>
        {
            h.Username(username);
            h.Password(password);
        });

        cfg.ReceiveEndpoint("payments-pedido-realizado", e =>
        {
            e.UseMessageRetry(r => r.Intervals(
                TimeSpan.FromSeconds(5),
                TimeSpan.FromSeconds(10),
                TimeSpan.FromSeconds(30)));

            e.UseEntityFrameworkOutbox<FcGamesContexto>(ctx);

            e.ConfigureConsumer<PedidoRealizadoEventoConsumer>(ctx);
        });
    });
});

var host = builder.Build();

using (var scope = host.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<FcGamesContexto>();
    db.Database.Migrate();
}

await host.RunAsync();
