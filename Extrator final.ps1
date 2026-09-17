<#
.SYNOPSIS
    Script autossuficiente para extrair arquivos de .zip com base em perfis inteligentes, usando apenas recursos nativos do Windows.
.DESCRIPTION
    1.  NÃO REQUER 7-Zip. Utiliza as funcionalidades de compressão nativas do PowerShell/.NET.
    2.  Analisa o conteúdo interno de um .zip para identificar e aplicar o perfil de extração correto (CCB, Histórico, etc.).
    3.  A estrutura robusta impede o fechamento automático da janela e trata erros corretamente.
    4.  Compatível com Windows 10/11 e Windows Server 2016 ou superior (requer PowerShell 5.1+).
#>

param ([string]$Path)

try {
    # Carrega a biblioteca de compressão do .NET
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    # Perfis de extração inteligente
    $extractionProfiles = @{
        'CCB_Profile' = @{ IdentifierPatterns = @('*_CCB_*.pdf'); Type = 'ExcludeAndSelect'; ExclusionPatterns = @('*TERM*') }
        'Historico_Profile' = @{ IdentifierPatterns = @('*Historico-da-Assinatura*.pdf'); Type = 'ExcludeAndSelect'; ExclusionPatterns = @('*ASSINADO*') }
        'Documentacao_Profile' = @{ IdentifierPatterns = @('*CNH*.pdf', '*RG*.pdf'); Type = 'ExcludeAndSelect'; ExclusionPatterns = @('*ASSINADO*') }
        'Declaracao_Profile' = @{ IdentifierPatterns = @('*DECLARACAO*.pdf'); Type = 'IncludeList'; InclusionPatterns = @('*') }
        'LGPD_Profile' = @{ IdentifierPatterns = @('*LGPD*.pdf'); Type = 'IncludeList'; InclusionPatterns = @('*') }
    }

    Clear-Host

    # Validações iniciais
    if (-not $Path) { $Path = Read-Host "Forneça o caminho do arquivo compactado"; $Path = $Path.Trim('"') }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Arquivo nao encontrado em '$Path'." }
    $fileInfo = Get-Item -LiteralPath $Path
    $outputDirectory = Read-Host "Forneça o caminho da pasta de destino para a extração"; $outputDirectory = $outputDirectory.Trim('"')
    if ([string]::IsNullOrWhiteSpace($outputDirectory)) { throw "O caminho de destino não pode ser vazio." }
    if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
        try { New-Item -ItemType Directory -Path $outputDirectory -Force -ErrorAction Stop | Out-Null; Write-Host "Diretório de destino '$outputDirectory' criado com sucesso." -F Green }
        catch { throw "Não foi possível criar o diretório de destino." }
    }

    Write-Host "================ ANALISANDO ARQUIVO: $($fileInfo.Name) ================" -F Cyan

    # Lista os arquivos usando .NET
    try {
        $zipArchive = [System.IO.Compression.ZipFile]::OpenRead($Path)
        $fileListOutput = $zipArchive.Entries.FullName
    } catch {
        throw "Falha ao ler o conteúdo do arquivo .zip. Verifique se o arquivo não está corrompido."
    } finally {
        if ($zipArchive) { $zipArchive.Dispose() }
    }
    
    # Lógica de seleção de perfil
    $activeProfile = $null; $profileName = "Nenhum"
    foreach ($profileEntry in $extractionProfiles.GetEnumerator()) {
        foreach ($identifier in $profileEntry.Value.IdentifierPatterns) {
            $matchFound = $false; foreach($line in $fileListOutput){ if($line -like $identifier){ $matchFound = $true; break } }; if ($matchFound) { $activeProfile = $profileEntry.Value; $profileName = $profileEntry.Name; break }
        }
        if ($activeProfile) { break }
    }
    
    if (-not $activeProfile) {
        Write-Host ""
        Write-Host "--- Conteúdo Encontrado no .zip (para diagnóstico) ---" -ForegroundColor Yellow
        $fileListOutput | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
        Write-Host "----------------------------------------------------" -ForegroundColor Yellow
        throw "Nenhum perfil de extração encontrado para o conteúdo deste .zip."
    }

    Write-Host "Conteúdo identificado. Usando o perfil: '$profileName' (Tipo: $($activeProfile.Type))" -F Magenta; Write-Host ""

    # Lógica de seleção de arquivos
    $filesToExtract = New-Object 'System.Collections.Generic.List[string]'
    
    switch ($activeProfile.Type) {
        'ExcludeAndSelect' {
            $folderContents = $fileListOutput | Where-Object { $_.Contains('/') } | Group-Object { ($_ -split '/')[0] }
            foreach ($folder in $folderContents) {
                
                $filesMatchingCriteria = $folder.Group | Where-Object {
                    $currentFile = $_
                    $isExcluded = $false
                    foreach ($pattern in $activeProfile.ExclusionPatterns) {
                        if ($currentFile -like $pattern) { $isExcluded = $true; break }
                    }
                    -not $isExcluded
                }
                
                # Adiciona os arquivos encontrados à lista principal como uma coleção (ArrayList)
                # para garantir que o .AddRange funcione corretamente.
                if ($filesMatchingCriteria) {
                    $filesToExtract.AddRange([System.Collections.Generic.List[string]]$filesMatchingCriteria)
                }
            }
        }
        'IncludeList' {
            foreach ($file in $fileListOutput) {
                if ($file -notlike '*/') {
                    foreach ($pattern in $activeProfile.InclusionPatterns) {
                        if ($file -like $pattern) { $filesToExtract.Add($file); break }
                    }
                }
            }
        }
    }
    
    $uniqueFiles = $filesToExtract | Sort-Object -Unique
    if ($uniqueFiles.Count -eq 0) { throw "Nenhum arquivo encontrado que corresponda às regras do perfil '$profileName'." }
    Write-Host "$($uniqueFiles.Count) arquivo(s) selecionado(s) para extração." -F Green

    # Etapa final: Extração
    Write-Host "Iniciando extração para '$outputDirectory'..."
    $duration = Measure-Command {
        try {
            $zipArchiveToExtract = [System.IO.Compression.ZipFile]::OpenRead($Path)
            foreach ($file in $uniqueFiles) {
                $entry = $zipArchiveToExtract.GetEntry($file)
                if ($entry) {
                    $destinationPath = Join-Path -Path $outputDirectory -ChildPath $entry.Name
                    $destinationDir = Split-Path -Path $destinationPath -Parent
                    if (-not (Test-Path -LiteralPath $destinationDir)) {
                        New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
                    }
                    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destinationPath, $true)
                }
            }
        }
        catch {
             throw "Ocorreu um erro durante a extração nativa: $($_.Exception.Message)"
        }
        finally {
            if ($zipArchiveToExtract) { $zipArchiveToExtract.Dispose() }
        }
    }
    
    $minutes = [Math]::Floor($duration.TotalMinutes); $seconds = $duration.Seconds; Write-Host ""; Write-Host "================ EXTRACAO CONCLUÍDA COM SUCESSO! ================" -F Green; Write-Host "  $($uniqueFiles.Count) arquivo(s) extraído(s) para '$outputDirectory'" -F Green; Write-Host "  Tempo total gasto: $minutes minuto(s) e $seconds segundo(s)." -F Green; Write-Host "==================================================================" -F Green
}
catch {
    Write-Host ""; Write-Host "!!!!!!!!!!!!!!! OCORREU UM ERRO DURANTE A EXECUÇÃO !!!!!!!!!!!!!!!" -F Red
    Write-Host "MOTIVO: $($_.Exception.Message)" -F Red
}
finally {
    Write-Host ""; Read-Host "Pressione Enter para fechar a janela"
}