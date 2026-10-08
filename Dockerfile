FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY nuget.config .
COPY app/src/ app/src/

WORKDIR /src/app/src

# Utiliza o secret montado dinamicamente para autenticar o restore sem expor o token
RUN --mount=type=secret,id=GITHUB_TOKEN \
    export NUGET_AUTH_TOKEN=$(cat /run/secrets/GITHUB_TOKEN) && \
    dotnet restore Fiap.FCGames.Payments.Api/Fiap.FCGames.Payments.Api.csproj    

# Compila e publica a aplicação
RUN --mount=type=secret,id=GITHUB_TOKEN \
    export NUGET_AUTH_TOKEN=$(cat /run/secrets/GITHUB_TOKEN) && \
    dotnet publish Fiap.FCGames.Payments.Api/Fiap.FCGames.Payments.Api.csproj -c Release -o /app/publish /p:UseAppHost=false    

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app

# Instala bibliotecas nativas de internacionalizacao e suporte a timezone
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    icu-devtools \
    libicu-dev \
    && rm -rf /var/lib/apt/lists/*    

EXPOSE 5003

ENV ASPNETCORE_URLS=http://+:5003
ENV ASPNETCORE_ENVIRONMENT=Production

COPY --from=build /app/publish .

ENTRYPOINT ["dotnet", "Fiap.FCGames.Payments.Api.dll"]
