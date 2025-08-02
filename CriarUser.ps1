# Script para Criação de Usuários no Microsoft Entra ID
# Requisitos: Módulo Microsoft.Graph instalado
# Install-Module Microsoft.Graph -Scope CurrentUser

param(
    [Parameter(Mandatory=$true)]
    [string]$DisplayName,
    
    [Parameter(Mandatory=$true)]
    [string]$UserPrincipalName,
    
    [Parameter(Mandatory=$false)]
    [string]$GivenName,
    
    [Parameter(Mandatory=$false)]
    [string]$Surname,
    
    [Parameter(Mandatory=$false)]
    [string]$JobTitle,
    
    [Parameter(Mandatory=$false)]
    [string]$Department,
    
    [Parameter(Mandatory=$false)]
    [string]$OfficeLocation,
    
    [Parameter(Mandatory=$false)]
    [string]$MobilePhone,
    
    [Parameter(Mandatory=$false)]
    [string]$BusinessPhone,
    
    [Parameter(Mandatory=$false)]
    [string]$ManagerUPN,
    
    [Parameter(Mandatory=$false)]
    [string[]]$GroupNames,
    
    [Parameter(Mandatory=$false)]
    [switch]$ForcePasswordChange = $true,
    
    [Parameter(Mandatory=$false)]
    [string]$LicenseSku
)

# Função para gerar senha aleatória
function Generate-RandomPassword {
    param([int]$Length = 12)
    
    $chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*"
    $password = ""
    for ($i = 0; $i -lt $Length; $i++) {
        $password += $chars[(Get-Random -Maximum $chars.Length)]
    }
    return $password
}

# Função para verificar se o módulo está instalado
function Test-GraphModule {
    if (!(Get-Module -ListAvailable -Name Microsoft.Graph)) {
        Write-Error "Módulo Microsoft.Graph não encontrado. Execute: Install-Module Microsoft.Graph -Scope CurrentUser"
        exit 1
    }
}

# Função principal para criar usuário
function New-EntraUser {
    try {
        # Verificar módulo
        Test-GraphModule
        
        # Conectar ao Microsoft Graph
        Write-Host "Conectando ao Microsoft Graph..." -ForegroundColor Yellow
        Connect-MgGraph -Scopes "User.ReadWrite.All", "Group.ReadWrite.All", "Directory.ReadWrite.All"
        
        # Gerar senha temporária
        $temporaryPassword = Generate-RandomPassword -Length 16
        
        # Preparar parâmetros do usuário
        $userParams = @{
            DisplayName = $DisplayName
            UserPrincipalName = $UserPrincipalName
            MailNickname = ($UserPrincipalName -split '@')[0]
            AccountEnabled = $true
            PasswordProfile = @{
                Password = $temporaryPassword
                ForceChangePasswordNextSignIn = $ForcePasswordChange
            }
        }
        
        # Adicionar campos opcionais se fornecidos
        if ($GivenName) { $userParams.GivenName = $GivenName }
        if ($Surname) { $userParams.Surname = $Surname }
        if ($JobTitle) { $userParams.JobTitle = $JobTitle }
        if ($Department) { $userParams.Department = $Department }
        if ($OfficeLocation) { $userParams.OfficeLocation = $OfficeLocation }
        if ($MobilePhone) { $userParams.MobilePhone = $MobilePhone }
        if ($BusinessPhone) { $userParams.BusinessPhones = @($BusinessPhone) }
        
        # Criar usuário
        Write-Host "Criando usuário: $DisplayName" -ForegroundColor Green
        $newUser = New-MgUser @userParams
        
        Write-Host "✓ Usuário criado com sucesso!" -ForegroundColor Green
        Write-Host "User ID: $($newUser.Id)" -ForegroundColor Cyan
        Write-Host "UPN: $($newUser.UserPrincipalName)" -ForegroundColor Cyan
        Write-Host "Senha temporária: $temporaryPassword" -ForegroundColor Yellow
        
        # Definir gerente se especificado
        if ($ManagerUPN) {
            try {
                $manager = Get-MgUser -Filter "userPrincipalName eq '$ManagerUPN'"
                if ($manager) {
                    $managerRef = @{
                        "@odata.id" = "https://graph.microsoft.com/v1.0/users/$($manager.Id)"
                    }
                    Set-MgUserManagerByRef -UserId $newUser.Id -BodyParameter $managerRef
                    Write-Host "✓ Gerente definido: $ManagerUPN" -ForegroundColor Green
                } else {
                    Write-Warning "Gerente não encontrado: $ManagerUPN"
                }
            } catch {
                Write-Warning "Erro ao definir gerente: $($_.Exception.Message)"
            }
        }
        
        # Adicionar a grupos se especificado
        if ($GroupNames) {
            foreach ($groupName in $GroupNames) {
                try {
                    $group = Get-MgGroup -Filter "displayName eq '$groupName'"
                    if ($group) {
                        $groupMember = @{
                            "@odata.id" = "https://graph.microsoft.com/v1.0/users/$($newUser.Id)"
                        }
                        New-MgGroupMember -GroupId $group.Id -BodyParameter $groupMember
                        Write-Host "✓ Adicionado ao grupo: $groupName" -ForegroundColor Green
                    } else {
                        Write-Warning "Grupo não encontrado: $groupName"
                    }
                } catch {
                    Write-Warning "Erro ao adicionar ao grupo $groupName : $($_.Exception.Message)"
                }
            }
        }
        
        # Atribuir licença se especificada
        if ($LicenseSku) {
            try {
                $license = Get-MgSubscribedSku | Where-Object { $_.SkuPartNumber -eq $LicenseSku }
                if ($license -and $license.PrepaidUnits.Enabled -gt 0) {
                    $licenseParams = @{
                        AddLicenses = @(
                            @{
                                SkuId = $license.SkuId
                                DisabledPlans = @()
                            }
                        )
                        RemoveLicenses = @()
                    }
                    Set-MgUserLicense -UserId $newUser.Id -BodyParameter $licenseParams
                    Write-Host "✓ Licença atribuída: $LicenseSku" -ForegroundColor Green
                } else {
                    Write-Warning "Licença não encontrada ou não disponível: $LicenseSku"
                }
            } catch {
                Write-Warning "Erro ao atribuir licença: $($_.Exception.Message)"
            }
        }
        
        # Exibir resumo
        Write-Host "`n=== RESUMO DA CRIAÇÃO ===" -ForegroundColor Magenta
        Write-Host "Nome: $DisplayName"
        Write-Host "UPN: $UserPrincipalName"
        Write-Host "ID: $($newUser.Id)"
        Write-Host "Senha temporária: $temporaryPassword"
        Write-Host "Forçar mudança de senha: $ForcePasswordChange"
        
        return $newUser
        
    } catch {
        Write-Error "Erro ao criar usuário: $($_.Exception.Message)"
        return $null
    } finally {
        # Desconectar
        Disconnect-MgGraph -ErrorAction SilentlyContinue
    }
}

# Exemplos de uso (comentados)
<#
# Exemplo 1: Usuário básico
New-EntraUser -DisplayName "João Silva" -UserPrincipalName "joao.silva@empresa.com"

# Exemplo 2: Usuário completo
New-EntraUser -DisplayName "Maria Santos" -UserPrincipalName "maria.santos@empresa.com" `
              -GivenName "Maria" -Surname "Santos" -JobTitle "Analista" `
              -Department "TI" -OfficeLocation "São Paulo" `
              -MobilePhone "+5511999999999" -BusinessPhone "+551133333333" `
              -ManagerUPN "gerente@empresa.com" `
              -GroupNames @("Grupo_TI", "Todos_Funcionarios") `
              -LicenseSku "ENTERPRISEPREMIUM" `
              -ForcePasswordChange:$true

# Exemplo 3: Execução via parâmetros do script
# .\CreateUser.ps1 -DisplayName "Pedro Costa" -UserPrincipalName "pedro.costa@empresa.com" -JobTitle "Desenvolvedor"
#>

# Verificar se foi chamado com parâmetros e executar
if ($DisplayName -and $UserPrincipalName) {
    $result = New-EntraUser
    if ($result) {
        Write-Host "`nUsuário criado com sucesso!" -ForegroundColor Green
    }
} else {
    Write-Host "Script carregado. Use New-EntraUser ou execute com parâmetros -DisplayName e -UserPrincipalName" -ForegroundColor Yellow
    Write-Host "Para ver exemplos, consulte os comentários no final do script." -ForegroundColor Cyan
}
