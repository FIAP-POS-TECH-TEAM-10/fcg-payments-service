using MassTransit;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace Fiap.FCGames.Payments.CrossCutting.Extensions;

public static class MassTransitExtensions
{
    /// <summary>
    /// Registra o MassTransit escolhendo o transporte pela config, sem exigir mudança no
    /// código de aplicação (IPublishEndpoint/Publish continuam iguais):
    ///   Messaging:Provider = "Sqs"      -> Amazon SQS + SNS (ECS/AWS; precisa de Task Role)
    ///   RabbitMQ:Host      definido     -> RabbitMQ (local / docker-compose)
    ///   nenhum dos dois                 -> in-memory (satisfaz a DI; Publish() vira no-op)
    /// Usado pelo projeto Api (publisher de PagamentoProcessadoEvento). O Worker (consumer
    /// de PedidoRealizadoEvento) tem o próprio registro em Program.cs, com os mesmos 3 transportes.
    /// </summary>
    public static IServiceCollection AddMassTransitMessaging(this IServiceCollection services, IConfiguration configuration)
    {
        var provider = configuration["Messaging:Provider"];
        var rabbitHost = configuration["RabbitMQ:Host"];

        services.AddMassTransit(x =>
        {
            if (string.Equals(provider, "Sqs", StringComparison.OrdinalIgnoreCase))
            {
                // Amazon SQS (fila) + SNS (fan-out/pub-sub) — equivalente ao exchange do RabbitMQ.
                // Credenciais: cadeia padrão do AWS SDK (no ECS, vem da Task Role via
                // AWS_CONTAINER_CREDENTIALS_RELATIVE_URI, injetado automaticamente pelo agente).
                var region = configuration["AWS:Region"] ?? "sa-east-1";

                x.UsingAmazonSqs((context, cfg) =>
                {
                    cfg.Host(region, h => { });
                    cfg.ConfigureEndpoints(context);
                });
            }
            else if (!string.IsNullOrWhiteSpace(rabbitHost))
            {
                x.UsingRabbitMq((_, cfg) =>
                {
                    var username = configuration["RabbitMQ:Username"] ?? "guest";
                    var password = configuration["RabbitMQ:Password"] ?? "guest";

                    cfg.Host(rabbitHost, "/", h =>
                    {
                        h.Username(username);
                        h.Password(password);
                    });
                });
            }
            else
            {
                // Sem broker configurado (ex.: deploy standalone sem RabbitMQ nem SQS habilitado).
                x.UsingInMemory((context, cfg) => cfg.ConfigureEndpoints(context));
            }
        });

        return services;
    }
}
