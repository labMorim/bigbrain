# ===============================================================================
# SCRIPT DE CRIAÇÃO DE USUÁRIO - MICROSOFT ENTRA ID
# Otimizado para N8N - Sem dependências de módulos PowerShell
# Usa Microsoft Graph API via Invoke-WebRequest
# ===============================================================================

param(
    # === PLACEHOLDERS PARA EDIÇÃO PELO LLM ===
    [Parameter(Mandatory=$true)]
    [string]$FirstName = "{{FIRST_NAME}}",
    
    [Parameter(Mandatory=$true)]
    [string]$LastName = "{{LAST_NAME}}",
    
    [Parameter(Mandatory=$true)]
    [string]$Domain = "{{DOMAIN}}",
    
    [Parameter(Mandatory=$false)]
    [string]$JobTitle = "{{JOB_TITLE}}",
    
    [Parameter(Mandatory=$false)]
    [string]$Department = "{{DEPARTMENT}}",
    
    [Parameter(Mandatory=$false)]
    [string]$OfficeLocation = "{{OFFICE_LOCATION}}",
    
    [Parameter(Mandatory=$false)]
    [string]$MobilePhone = "{{MOBILE_PHONE}}",
    
    [Parameter(Mandatory=$false)]
    [string]$License = "{{LICENSE_SKU}}",
    
    [Parameter(Mandatory=$false)]
    [string[]]$Groups = @("{{GROUP_1}}", "{{GROUP_2}}"),
    
    [Parameter(Mandatory=$false)]
    [string]$ManagerEmail = "{{MANAGER_EMAIL}}",
    
    # === CREDENCIAIS DO SERVICE PRINCIPAL ===
    [Parameter(Mandatory=$true)]
    [string]$TenantId = "{{TENANT_ID}}",
    
    [Parameter(Mandatory=$true)]
    [string]$ClientId = "{{CLIENT_ID}}",
    
    [Parameter(Mandatory=$true)]
    [string]$ClientSecret = "{{CLIENT_SECRET}}"
)

# ===============================================================================
# CONFIGURAÇÕES E VARIÁVEIS
# ===============================================================================

# URLs da Microsoft Graph API
$GraphBaseUrl = "https://graph.microsoft.com/v1.0"
$TokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

# Variáveis derivadas dos parâmetros
$DisplayName = "$FirstName $LastName"
$UserPrincipalName = "$($FirstName.ToLower()).$($LastName.ToLower())@$Domain"
$MailNickname = "$($FirstName.ToLower()).$($LastName.ToLower())"

# ===============================================================================
# FUNÇÕES AUXILIARES
# ===============================================================================

function Get-AccessToken {
    param($TenantId, $ClientId, $ClientSecret)
    
    $Body = @{
        grant_type = "client_credentials"
        scope = "https://graph.microsoft.com/.default"
        client_id = $ClientId
        client_secret = $ClientSecret
    }
    
    try {
        $Response = Invoke-RestMethod -Uri $TokenUrl -Method POST -Body $Body -ContentType "application/x-www-form-urlencoded"
        return $Response.access_token
    }
    catch {
        Write-Error "Erro ao obter token de acesso: $($_.Exception.Message)"
        throw
    }
}

function Generate-SecurePassword {
    param([int]$Length = 16)
    
    $chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*"
    $password = ""
    for ($i = 0; $i -lt $Length; $i++) {
        $password += $chars[(Get-Random -Maximum $chars.Length)]
    }
    return $password
}

function Invoke-GraphAPI {
    param(
        [string]$AccessToken,
        [string]$Uri,
        [string]$Method = "GET",
        [object]$Body = $null
    )
    
    $Headers = @{
        Authorization = "Bearer $AccessToken"
        "Content-Type" = "application/json"
    }
    
    $Params = @{
        Uri = $Uri
        Method = $Method
        Headers = $Headers
    }
    
    if ($Body) {
        $Params.Body = ($Body | ConvertTo-Json -Depth 10)
    }
    
    try {
        return Invoke-RestMethod @Params
    }
    catch {
        $ErrorDetails = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($ErrorDetails) {
            Write-Error "Graph API Error: $($ErrorDetails.error.message)"
        } else {
            Write-Error "Graph API Error: $($_.Exception.Message)"
        }
        throw
    }
}

# ===============================================================================
# SCRIPT PRINCIPAL
# ===============================================================================

try {
    Write-Host "=== INICIANDO CRIAÇÃO DE USUÁRIO ===" -ForegroundColor Cyan
    Write-Host "Usuário: $DisplayName ($UserPrincipalName)" -ForegroundColor Yellow
    
    # 1. OBTER TOKEN DE ACESSO
    Write-Host "`n[1/6] Obtendo token de acesso..." -ForegroundColor Green
    $AccessToken = Get-AccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
    Write-Host "✓ Token obtido com sucesso" -ForegroundColor Green
    
    # 2. GERAR SENHA TEMPORÁRIA
    Write-Host "`n[2/6] Gerando senha temporária..." -ForegroundColor Green
    $TempPassword = Generate-SecurePassword -Length 16
    Write-Host "✓ Senha gerada: $TempPassword" -ForegroundColor Yellow
    
    # 3. CRIAR USUÁRIO
    Write-Host "`n[3/6] Criando usuário..." -ForegroundColor Green
    
    $UserBody = @{
        displayName = $DisplayName
        userPrincipalName = $UserPrincipalName
        mailNickname = $MailNickname
        accountEnabled = $true
        passwordProfile = @{
            password = $TempPassword
            forceChangePasswordNextSignIn = $true
        }
    }
    
    # Adicionar campos opcionais se não forem placeholders
    if ($FirstName -ne "{{FIRST_NAME}}") { $UserBody.givenName = $FirstName }
    if ($LastName -ne "{{LAST_NAME}}") { $UserBody.surname = $LastName }
    if ($JobTitle -ne "{{JOB_TITLE}}" -and $JobTitle) { $UserBody.jobTitle = $JobTitle }
    if ($Department -ne "{{DEPARTMENT}}" -and $Department) { $UserBody.department = $Department }
    if ($OfficeLocation -ne "{{OFFICE_LOCATION}}" -and $OfficeLocation) { $UserBody.officeLocation = $OfficeLocation }
    if ($MobilePhone -ne "{{MOBILE_PHONE}}" -and $MobilePhone) { $UserBody.mobilePhone = $MobilePhone }
    
    $NewUser = Invoke-GraphAPI -AccessToken $AccessToken -Uri "$GraphBaseUrl/users" -Method "POST" -Body $UserBody
    Write-Host "✓ Usuário criado: $($NewUser.id)" -ForegroundColor Green
    
    # 4. DEFINIR GERENTE (se especificado)
    if ($ManagerEmail -ne "{{MANAGER_EMAIL}}" -and $ManagerEmail) {
        Write-Host "`n[4/6] Definindo gerente..." -ForegroundColor Green
        try {
            $Manager = Invoke-GraphAPI -AccessToken $AccessToken -Uri "$GraphBaseUrl/users?`$filter=userPrincipalName eq '$ManagerEmail'"
            if ($Manager.value -and $Manager.value.Count -gt 0) {
                $ManagerRef = @{
                    "@odata.id" = "$GraphBaseUrl/users/$($Manager.value[0].id)"
                }
                Invoke-GraphAPI -AccessToken $AccessToken -Uri "$GraphBaseUrl/users/$($NewUser.id)/manager/`$ref" -Method "PUT" -Body $ManagerRef
                Write-Host "✓ Gerente definido: $ManagerEmail" -ForegroundColor Green
            } else {
                Write-Warning "Gerente não encontrado: $ManagerEmail"
            }
        }
        catch {
            Write-Warning "Erro ao definir gerente: $($_.Exception.Message)"
        }
    } else {
        Write-Host "`n[4/6] Pulando definição de gerente (não especificado)" -ForegroundColor Yellow
    }
    
    # 5. ADICIONAR A GRUPOS (se especificados)
    if ($Groups -and $Groups[0] -ne "{{GROUP_1}}") {
        Write-Host "`n[5/6] Adicionando a grupos..." -ForegroundColor Green
        foreach ($GroupName in $Groups) {
            if ($GroupName -and $GroupName -notlike "{{*}}") {
                try {
                    $Group = Invoke-GraphAPI -AccessToken $AccessToken -Uri "$GraphBaseUrl/groups?`$filter=displayName eq '$GroupName'"
                    if ($Group.value -and $Group.value.Count -gt 0) {
                        $MemberRef = @{
                            "@odata.id" = "$GraphBaseUrl/users/$($NewUser.id)"
                        }
                        Invoke-GraphAPI -AccessToken $AccessToken -Uri "$GraphBaseUrl/groups/$($Group.value[0].id)/members/`$ref" -Method "POST" -Body $MemberRef
                        Write-Host "✓ Adicionado ao grupo: $GroupName" -ForegroundColor Green
                    } else {
                        Write-Warning "Grupo não encontrado: $GroupName"
                    }
                }
                catch {
                    Write-Warning "Erro ao adicionar ao grupo $GroupName : $($_.Exception.Message)"
                }
            }
        }
    } else {
        Write-Host "`n[5/6] Pulando adição a grupos (não especificados)" -ForegroundColor Yellow
    }
    
    # 6. ATRIBUIR LICENÇA (se especificada)
    if ($License -ne "{{LICENSE_SKU}}" -and $License) {
        Write-Host "`n[6/6] Atribuindo licença..." -ForegroundColor Green
        try {
            $Skus = Invoke-GraphAPI -AccessToken $AccessToken -Uri "$GraphBaseUrl/subscribedSkus"
            $TargetSku = $Skus.value | Where-Object { $_.skuPartNumber -eq $License }
            
            if ($TargetSku -and $TargetSku.prepaidUnits.enabled -gt 0) {
                $LicenseBody = @{
                    addLicenses = @(
                        @{
                            skuId = $TargetSku.skuId
                            disabledPlans = @()
                        }
                    )
                    removeLicenses = @()
                }
                Invoke-GraphAPI -AccessToken $AccessToken -Uri "$GraphBaseUrl/users/$($NewUser.id)/assignLicense" -Method "POST" -Body $LicenseBody
                Write-Host "✓ Licença atribuída: $License" -ForegroundColor Green
            } else {
                Write-Warning "Licença não encontrada ou indisponível: $License"
            }
        }
        catch {
            Write-Warning "Erro ao atribuir licença: $($_.Exception.Message)"
        }
    } else {
        Write-Host "`n[6/6] Pulando atribuição de licença (não especificada)" -ForegroundColor Yellow
    }
    
    # RESUMO FINAL
    Write-Host "`n=== USUÁRIO CRIADO COM SUCESSO ===" -ForegroundColor Magenta
    Write-Host "Nome: $DisplayName" -ForegroundColor White
    Write-Host "UPN: $UserPrincipalName" -ForegroundColor White
    Write-Host "ID: $($NewUser.id)" -ForegroundColor White
    Write-Host "Senha temporária: $TempPassword" -ForegroundColor Yellow
    Write-Host "Deve alterar senha no próximo login: Sim" -ForegroundColor White
    
    # Retorno estruturado para N8N
    $Result = @{
        success = $true
        userId = $NewUser.id
        userPrincipalName = $UserPrincipalName
        displayName = $DisplayName
        temporaryPassword = $TempPassword
        message = "Usuário criado com sucesso"
    }
    
    return ($Result | ConvertTo-Json -Depth 2)
}
catch {
    Write-Host "`n=== ERRO NA CRIAÇÃO DO USUÁRIO ===" -ForegroundColor Red
    Write-Host "Erro: $($_.Exception.Message)" -ForegroundColor Red
    
    $ErrorResult = @{
        success = $false
        error = $_.Exception.Message
        message = "Falha na criação do usuário"
    }
    
    return ($ErrorResult | ConvertTo-Json -Depth 2)
}

# ===============================================================================
# EXEMPLO DE USO NO N8N
# ===============================================================================
<#
# O LLM pode editar os placeholders assim:
$FirstName = "João"
$LastName = "Silva" 
$Domain = "empresa.com"
$JobTitle = "Desenvolvedor"
$Department = "TI"
$License = "ENTERPRISEPREMIUM"
$Groups = @("Desenvolvedores", "TI_Geral")
$ManagerEmail = "gerente@empresa.com"

# Credenciais do Service Principal (configurar no N8N como variáveis de ambiente)
$TenantId = $env:AZURE_TENANT_ID
$ClientId = $env:AZURE_CLIENT_ID  
$ClientSecret = $env:AZURE_CLIENT_SECRET
#>
