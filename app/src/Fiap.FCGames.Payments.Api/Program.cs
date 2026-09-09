using Fiap.FCGames.Payments.CrossCutting.Extensions;
using Fiap.FCGames.Payments.CrossCutting.Middleware;
using Fiap.FCGames.Payments.Infra.DataProvider.Contexto;
using Microsoft.EntityFrameworkCore;
using Serilog;
using Prometheus;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.Configure<Microsoft.AspNetCore.Mvc.ApiBehaviorOptions>(options =>
    options.SuppressModelStateInvalidFilter = true);
builder.Services.AddOpenApi();

builder.Services.RegisterDI();
builder.Services.AddMediatRConfiguration();

builder.Services.RegisterSwaggerGenerator();

builder.Services.AddAutenticacaoApi(builder.Configuration);
builder.Services.AddAutorizacaoApi();

builder.Services.AddContextDatabase(builder.Configuration);
builder.Services.AddMassTransitRabbitMq(builder.Configuration);

builder.Services.AddHealthChecks();

Log.Logger = new LoggerConfiguration()
    .ReadFrom.Configuration(builder.Configuration)
    .Enrich.FromLogContext()
    .CreateLogger();

builder.Host.UseSerilog();

var app = builder.Build();

if (!app.Environment.IsEnvironment("Testing"))
{
    using var scope = app.Services.CreateScope();
    var dbContext = scope.ServiceProvider.GetRequiredService<FcGamesContexto>();
    dbContext.Database.Migrate();
}

app.UseCorrelationId();

// Middleware para métricas HTTP (latência, status code, etc.)
app.UseRouting();
app.UseHttpMetrics();

// Endpoint padrão /metrics
app.MapMetrics();

if (app.Environment.IsDevelopment())
{
    app.RegisterSwagger();
    app.MapOpenApi();
    app.RegisterScalar();
}

app.UseErrorHandlingMiddleware();
app.UseHttpsRedirection();
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();
app.MapHealthChecks("/health");

await app.RunAsync();
