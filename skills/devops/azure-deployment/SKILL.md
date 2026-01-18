---
name: azure-deployment
description: Best practices for deploying ASP.NET Core applications to Azure including App Service, Container Apps, AKS, and configuration management.
version: 1.0.0
priority: medium
categories:
  - devops
  - azure
  - deployment
use_when:
  - "When deploying to Azure App Service"
  - "When using Azure Container Apps"
  - "When deploying to AKS"
  - "When configuring Azure resources"
prerequisites:
  - "Azure subscription"
  - "Azure CLI or PowerShell"
related_skills:
  - docker-containerization
  - ci-cd-pipelines
---

# Azure Deployment Best Practices

## Overview

This skill covers deploying ASP.NET Core applications to Azure services including App Service, Container Apps, and Azure Kubernetes Service (AKS).

## Rules

### Rule 1: Configure App Service Properly

**Priority**: High

**Description**: Configure Azure App Service with proper settings, scaling, and health checks.

**Incorrect**:

```bash
# Basic deployment without configuration
az webapp up --name myapp --resource-group myrg
# Missing health checks, scaling, etc.
```

**Correct**:

```bash
# Create App Service Plan
az appservice plan create \
  --name myapp-plan \
  --resource-group myrg \
  --sku B1 \
  --is-linux

# Create Web App
az webapp create \
  --name myapp \
  --resource-group myrg \
  --plan myapp-plan \
  --runtime "DOTNET|8.0"

# Configure app settings
az webapp config appsettings set \
  --name myapp \
  --resource-group myrg \
  --settings \
    ASPNETCORE_ENVIRONMENT=Production \
    ConnectionStrings__DefaultConnection="$CONNECTION_STRING"

# Configure health check
az webapp config set \
  --name myapp \
  --resource-group myrg \
  --generic-configurations '{"healthCheckPath": "/health"}'

# Configure scaling
az monitor autoscale create \
  --name myapp-autoscale \
  --resource-group myrg \
  --resource /subscriptions/{sub-id}/resourceGroups/myrg/providers/Microsoft.Web/serverfarms/myapp-plan \
  --min-count 1 \
  --max-count 10 \
  --count 2
```

**Why**:
- Proper resource configuration
- Health monitoring
- Auto-scaling
- Production-ready setup

---

### Rule 2: Use Deployment Slots

**Priority**: High

**Description**: Use deployment slots for zero-downtime deployments.

**Correct**:

```bash
# Create staging slot
az webapp deployment slot create \
  --name myapp \
  --resource-group myrg \
  --slot staging

# Deploy to staging
az webapp deployment source config-zip \
  --name myapp \
  --resource-group myrg \
  --slot staging \
  --src app.zip

# Swap slots (zero downtime)
az webapp deployment slot swap \
  --name myapp \
  --resource-group myrg \
  --slot staging \
  --target-slot production
```

**Why**:
- Zero-downtime deployments
- Test in production-like environment
- Easy rollback
- Better deployment confidence

---

### Rule 3: Secure Configuration

**Priority**: Critical

**Description**: Use Azure Key Vault for secrets and sensitive configuration.

**Incorrect**:

```bash
# Secrets in app settings - not secure
az webapp config appsettings set \
  --settings "ApiKey=secret123"
```

**Correct**:

```bash
# Create Key Vault
az keyvault create \
  --name myapp-vault \
  --resource-group myrg

# Store secret
az keyvault secret set \
  --vault-name myapp-vault \
  --name ApiKey \
  --value "secret123"

# Configure managed identity
az webapp identity assign \
  --name myapp \
  --resource-group myrg

# Grant access to Key Vault
az keyvault set-policy \
  --name myapp-vault \
  --object-id <webapp-identity-id> \
  --secret-permissions get list

# Reference Key Vault in app settings
az webapp config appsettings set \
  --name myapp \
  --resource-group myrg \
  --settings \
    ApiKey="@Microsoft.KeyVault(SecretUri=https://myapp-vault.vault.azure.net/secrets/ApiKey/)"
```

**Why**:
- Secure secret management
- Centralized secrets
- Audit trail
- Compliance requirements

---

### Rule 4: Configure Container Apps

**Priority**: Medium

**Description**: Deploy to Azure Container Apps for serverless container hosting.

**Correct**:

```bash
# Create Container Apps environment
az containerapp env create \
  --name myapp-env \
  --resource-group myrg \
  --location eastus

# Create Container App
az containerapp create \
  --name myapp \
  --resource-group myrg \
  --environment myapp-env \
  --image acr.azurecr.io/myapp:latest \
  --target-port 8080 \
  --ingress external \
  --min-replicas 1 \
  --max-replicas 10 \
  --cpu 0.5 \
  --memory 1.0Gi \
  --env-vars \
    ASPNETCORE_ENVIRONMENT=Production \
    ConnectionStrings__DefaultConnection="$CONNECTION_STRING"
```

**Why**:
- Serverless containers
- Auto-scaling
- Pay-per-use
- Modern deployment option

---

## Integration Example

Complete Azure deployment:

```bash
#!/bin/bash
# Deploy script

# Variables
RESOURCE_GROUP="myapp-rg"
APP_NAME="myapp"
LOCATION="eastus"

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create App Service Plan
az appservice plan create \
  --name "${APP_NAME}-plan" \
  --resource-group $RESOURCE_GROUP \
  --sku B1 \
  --is-linux

# Create Web App
az webapp create \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --plan "${APP_NAME}-plan" \
  --runtime "DOTNET|8.0"

# Configure
az webapp config set \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --always-on true \
  --health-check-path "/health"

# Deploy
az webapp deployment source config-zip \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --src app.zip
```

## Checklist

- [ ] App Service configured properly
- [ ] Deployment slots used
- [ ] Key Vault for secrets
- [ ] Health checks configured
- [ ] Auto-scaling configured
- [ ] Monitoring enabled
- [ ] Backup configured

## References

- [Azure App Service](https://docs.microsoft.com/azure/app-service/)
- [Azure Container Apps](https://docs.microsoft.com/azure/container-apps/)

## Changelog

### v1.0.0
- Initial release
- 4 core rules for Azure deployment
