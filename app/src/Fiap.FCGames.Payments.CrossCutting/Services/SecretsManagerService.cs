using Amazon.SecretsManager;
using System;
using System.Collections.Generic;
using System.Text;

namespace Fiap.FCGames.Payments.CrossCutting.Services;

public class SecretsManagerService
{
    private readonly IAmazonSecretsManager _secretsManager;
    private readonly string _secretName;

    public SecretsManagerService(IAmazonSecretsManager secretsManager, string secretName)
    {
        _secretsManager = secretsManager;
        _secretName = secretName;
    }

    public async Task<string> GetSecretAsync(CancellationToken cancellationToken = default)
    {
        var request = new Amazon.SecretsManager.Model.GetSecretValueRequest
        {
            SecretId = _secretName,
            VersionStage = "AWSCURRENT"
        };
        var response = await _secretsManager.GetSecretValueAsync(request, cancellationToken);
        return response.SecretString;
    }
}
