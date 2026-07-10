# Azure DevOps Pipelines: CI/CD Infrastructure as Code

**Pillar:** Azure Infrastructure
**SEO Target:** azure devops pipelines terraform ci/cd yaml environments
**Word Count:** ~1500

Azure DevOps Pipelines delivers CI/CD for any language targeting any cloud. YAML pipelines, environments with approvals, deployment strategies, and variable groups make it enterprise-ready. This guide implements a full CI/CD pipeline for a containerized application with Terraform deployment stages.

## Pipeline YAML Structure

```yaml
# azure-pipelines.yml
trigger:
  branches:
    include: [main, release/*]
  paths:
    include: [src/**, Dockerfile, k8s/**]

pr:
  branches:
    include: [main]

variables:
  - group: production-secrets
  - name: containerRegistry
    value: citadelacr.azurecr.io
  - name: imageRepository
    value: citadel-api
  - name: dockerfilePath
    value: Dockerfile

stages:
- stage: Build
  displayName: Build and Test
  jobs:
  - job: BuildAndTest
    pool:
      vmImage: ubuntu-latest
    steps:
    - task: UsePythonVersion@0
      inputs:
        versionSpec: '3.12'
    
    - script: |
        pip install -r requirements.txt
        pytest tests/ --junitxml=test-results.xml --cov=src --cov-report=xml
      displayName: Run tests

    - task: PublishTestResults@2
      inputs:
        testResultsFiles: test-results.xml
        testRunTitle: Unit Tests
      condition: always()
    
    - task: PublishCodeCoverageResults@2
      inputs:
        summaryFileLocation: coverage.xml

    - task: Docker@2
      displayName: Build image
      inputs:
        containerRegistry: $(containerRegistryServiceConnection)
        repository: $(imageRepository)
        command: build
        Dockerfile: $(dockerfilePath)
        tags: |
          $(Build.BuildId)
          $(Build.SourceBranchName)-latest

    - task: Docker@2
      displayName: Push image
      condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
      inputs:
        containerRegistry: $(containerRegistryServiceConnection)
        repository: $(imageRepository)
        command: push
        tags: |
          $(Build.BuildId)
          latest

- stage: DeployStaging
  displayName: Deploy to Staging
  dependsOn: Build
  condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
  jobs:
  - deployment: DeployStaging
    environment: staging
    pool:
      vmImage: ubuntu-latest
    strategy:
      runOnce:
        deploy:
          steps:
          - task: KubernetesManifest@1
            displayName: Deploy to AKS
            inputs:
              action: deploy
              connectionType: azureResourceManager
              azureSubscriptionConnection: $(azureServiceConnection)
              azureResourceGroup: $(resourceGroup)
              kubernetesCluster: $(aksCluster)
              namespace: staging
              manifests: k8s/staging/*.yaml
              containers: $(containerRegistry)/$(imageRepository):$(Build.BuildId)

- stage: DeployProduction
  displayName: Deploy to Production
  dependsOn: DeployStaging
  condition: succeeded()
  jobs:
  - deployment: DeployProduction
    environment: production
    pool:
      vmImage: ubuntu-latest
    strategy:
      canary:
        increments: [25, 50]
        preDeploy:
          steps:
          - script: echo "Pre-deploy health checks"
        deploy:
          steps:
          - task: KubernetesManifest@1
            inputs:
              action: deploy
              manifests: k8s/production/*.yaml
              containers: $(containerRegistry)/$(imageRepository):$(Build.BuildId)
        postRouteSuffix:
          steps:
          - script: echo "Post-route smoke tests"
```

## Terraform via Pipeline

```hcl
resource "azuredevops_build_definition" "terraform" {
  project_id = azuredevops_project.main.id
  name       = "Terraform Infrastructure"

  ci_trigger { use_yaml = true }
  pull_request_trigger { use_yaml = true }

  repository {
    repo_type   = "TfsGit"
    repo_id     = azuredevops_git_repository.main.id
    branch_name = "main"
    yml_path    = ".azure/terraform-pipeline.yml"
  }

  variable_groups = [
    azuredevops_variable_group.terraform.id
  ]
}
```

## Production Checklist

- [ ] Pipeline triggers on main + release branches, not every branch
- [ ] Multi-stage: Build → Staging → Production with approval gates
- [ ] Test results and coverage published as pipeline artifacts
- [ ] Environment resource (AKS namespace) linked to pipeline environment for traceability
- [ ] Canary deployment strategy on production (25% → 50% → 100%)
- [ ] Service connections (not personal PATs) for Azure and ACR
- [ ] Variable groups for secrets (not hardcoded in YAML)
- [ ] Terraform plan as PR comment; apply only on main merge

Azure DevOps Pipelines with environment approvals gives you a hard gate before production: the release manager reviews the staging smoke test results and clicks Approve. No automated deployment to production without a human sign-off.

## About This Guide

This guide is part of the Citadel Cloud Management content series covering AWS, Azure, GCP, DevSecOps, MCP Servers, and Cloud Careers. Follow our GitHub: https://github.com/kogunlowo123/citadel-cloud-management
