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

// Transporte escolhido pela config (Messaging:Provider=Sqs usa Amazon SQS/SNS na AWS;
// senão, se RabbitMQ:Host estiver definido, usa RabbitMQ como hoje — local/docker-compose).
// Consumer, retry policy e nome do endpoint ("payments-pedido-realizado" — convenção do
// CLAUDE.md) são os mesmos nos dois transportes.
var messagingProvider = builder.Configuration["Messaging:Provider"];
var rabbitHost = builder.Configuration["RabbitMQ:Host"];

builder.Services.AddMassTransit(x =>
{
    x.AddConsumer<PedidoRealizadoEventoConsumer>();

    if (string.Equals(messagingProvider, "Sqs", StringComparison.OrdinalIgnoreCase))
    {
        // Credenciais: cadeia padrão do AWS SDK (Task Role do ECS via
        // AWS_CONTAINER_CREDENTIALS_RELATIVE_URI, injetado automaticamente pelo agente).
        var region = builder.Configuration["AWS:Region"] ?? "sa-east-1";

        x.UsingAmazonSqs((ctx, cfg) =>
        {
            cfg.Host(region, h => { });

            cfg.ReceiveEndpoint("payments-pedido-realizado", e =>
            {
                e.UseMessageRetry(r => r.Intervals(
                    TimeSpan.FromSeconds(5),
                    TimeSpan.FromSeconds(10),
                    TimeSpan.FromSeconds(30)));

                e.ConfigureConsumer<PedidoRealizadoEventoConsumer>(ctx);
            });
        });
    }
    else if (!string.IsNullOrWhiteSpace(rabbitHost))
    {
        x.UsingRabbitMq((ctx, cfg) =>
        {
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

                e.ConfigureConsumer<PedidoRealizadoEventoConsumer>(ctx);
            });
        });
    }
    else
    {
        // Sem broker configurado — satisfaz a DI, consumer fica sem receber nada.
        x.UsingInMemory((ctx, cfg) => cfg.ConfigureEndpoints(ctx));
    }
});

var host = builder.Build();

using (var scope = host.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<FcGamesContexto>();
    db.Database.Migrate();
}

await host.RunAsync();
