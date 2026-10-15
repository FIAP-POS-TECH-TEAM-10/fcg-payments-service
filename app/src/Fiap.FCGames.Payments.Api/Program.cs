using Fiap.FCGames.Payments.CrossCutting.Extensions;
using Fiap.FCGames.Payments.CrossCutting.Middleware;
using Fiap.FCGames.Payments.CrossCutting.Services;
using Fiap.FCGames.Payments.Infra.DataProvider.Contexto;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.EntityFrameworkCore;
using Serilog;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddAwsSecretsManager(builder.Configuration);

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
builder.Services.AddMassTransitMessaging(builder.Configuration);

builder.Services.AddHealthChecks();

Log.Logger = new LoggerConfiguration()
    .ReadFrom.Configuration(builder.Configuration)
    .Enrich.FromLogContext()
    .CreateLogger();

builder.Host.UseSerilog();

var app = builder.Build();

//TESTA A CONEXÃO COM O SECRETS MANAGER DA AWS
try
{
    var secretsService =
        app.Services.GetRequiredService<SecretsManagerService>();

    var secret = await secretsService.GetSecretAsync();

    if (string.IsNullOrWhiteSpace(secret))
    {
        throw new InvalidOperationException("O segredo está vazio.");
    }

    app.Logger.LogInformation(
        "Sucesso! O segredo foi recuperado da AWS.");
}
catch (Exception ex)
{
    app.Logger.LogError(ex, "Falha ao acessar o segredo da AWS.");
    throw;
}

if (!app.Environment.IsEnvironment("Testing"))
{
    using var scope = app.Services.CreateScope();
    var dbContext = scope.ServiceProvider.GetRequiredService<FcGamesContexto>();
    dbContext.Database.Migrate();
}

app.UseCorrelationId();

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

app.MapHealthChecks("/health/live", new HealthCheckOptions
{
    Predicate = check => check.Tags.Contains("live")
});


await app.RunAsync();
