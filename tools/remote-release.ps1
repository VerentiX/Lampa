param([string]$GradleTask = "assembleRelease")

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$sshExe = "$env:WINDIR\System32\OpenSSH\ssh.exe"
$scpExe = "$env:WINDIR\System32\OpenSSH\scp.exe"
$keyPath = "C:\Users\Petr\.ssh\id_ed25519_android_build"
$remote = "zizpetya@93.92.204.168"
$port = 7846
$remoteBase = "/home/zizpetya/android-remote-build/v2rayng"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "v2rayng-remote-release-$stamp"
$sourceArchive = Join-Path $tempRoot "source.tar.gz"
$artifactArchive = Join-Path $tempRoot "release-artifacts.tar.gz"
$outputDir = Join-Path (Join-Path $projectRoot "remote-release") $stamp

foreach ($required in @($sshExe, $scpExe, $keyPath)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Required file not found: $required" }
}
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
    Write-Host "[1/4] Packaging project sources..." -ForegroundColor Cyan
    Push-Location $projectRoot
    try {
        & tar.exe -czf $sourceArchive `
            --exclude=.git --exclude=.gradle --exclude=.idea/workspace.xml `
            --exclude=remote-release --exclude='*/build' --exclude='*/build/*' `
            --exclude=app/fdroid/release --exclude='app/fdroid/release/*' `
            --exclude='*.bak*' `
            --exclude=tmp_libv2ray --exclude=_diag --exclude='*.log' --exclude='all_logs*.txt' `
            --exclude='tmp_*' --exclude=local.properties .
        if ($LASTEXITCODE -ne 0) { throw "Failed to create source archive" }
    } finally { Pop-Location }

    $archiveMb = [math]::Round((Get-Item -LiteralPath $sourceArchive).Length / 1MB, 1)
    Write-Host "[2/4] Uploading $archiveMb MB to build server..." -ForegroundColor Cyan
    & $sshExe -p $port -i $keyPath -o BatchMode=yes $remote "mkdir -p '$remoteBase'"
    if ($LASTEXITCODE -ne 0) { throw "Could not prepare remote build directory" }
    & $scpExe -q -P $port -i $keyPath -o BatchMode=yes $sourceArchive "${remote}:${remoteBase}-source.tar.gz"
    if ($LASTEXITCODE -ne 0) { throw "Source upload failed" }

    Write-Host "[3/4] Building $GradleTask on 16-thread server..." -ForegroundColor Cyan
    $remoteCommand = @"
set -e
BASE='$remoteBase'
STAGING="`${BASE}-staging"
WORK="`${BASE}/work"
SDK='/home/zizpetya/android-sdk'
GRADLE_HOME="`${BASE}/gradle-home"
rm -rf "`$STAGING"
mkdir -p "`$STAGING" "`$WORK" "`$GRADLE_HOME"
tar -xzf "${remoteBase}-source.tar.gz" -C "`$STAGING"
rsync -a --delete --exclude='.gradle/' --exclude='build/' --exclude='*/build/' "`$STAGING/" "`$WORK/"
printf 'sdk.dir=%s\n' "`$SDK" > "`$WORK/local.properties"
sed -i 's/\r`$//' "`$WORK/gradlew"
chmod +x "`$WORK/gradlew"
cd "`$WORK"
ANDROID_HOME="`$SDK" ANDROID_SDK_ROOT="`$SDK" GRADLE_USER_HOME="`$GRADLE_HOME" ./gradlew --build-cache --parallel $GradleTask
find app/build/outputs -type f \( -name '*.apk' -o -name '*.aab' -o -name 'mapping.txt' \) -print0 | tar --null -czf "`${BASE}-artifacts.tar.gz" --files-from=-
"@
    & $sshExe -p $port -i $keyPath -o BatchMode=yes $remote $remoteCommand
    if ($LASTEXITCODE -ne 0) { throw "Remote Gradle build failed" }

    Write-Host "[4/4] Downloading release artifacts..." -ForegroundColor Cyan
    & $scpExe -q -P $port -i $keyPath -o BatchMode=yes "${remote}:${remoteBase}-artifacts.tar.gz" $artifactArchive
    if ($LASTEXITCODE -ne 0) { throw "Artifact download failed" }
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    & tar.exe -xzf $artifactArchive -C $outputDir
    if ($LASTEXITCODE -ne 0) { throw "Failed to extract release artifacts" }

    Write-Host "Remote release build completed:" -ForegroundColor Green
    Write-Host $outputDir -ForegroundColor Green
    Get-ChildItem -LiteralPath $outputDir -Recurse -File | ForEach-Object {
        Write-Host ("  {0} ({1:N1} MB)" -f $_.FullName, ($_.Length / 1MB))
    }
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}
