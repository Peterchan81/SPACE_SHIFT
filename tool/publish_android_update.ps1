<#
.SYNOPSIS
  SPACE SHIFT Android 무선 업데이트 배포 — Supabase Storage(공개 버킷) 자동 배포.

.DESCRIPTION
  Galaxy Tab의 SPACE SHIFT 앱이 USB/ADB 없이 인터넷으로 새 버전을 감지·
  다운로드·설치할 수 있도록, PC1에서 만든 release APK와 그 메타데이터
  (version.json)를 Supabase Storage 공개 버킷에 올린다.

  NOMPASS V1(이 저장소와 무관한 별도 프로젝트)이 이미 실기로 검증한 것과
  같은 구조 — Supabase CLI의 `storage cp`(experimental)는 이 프로젝트에서도
  LegacyStorageUnsupportedOperationError로 실패할 수 있으므로, 표준 AWS
  CLI로 Supabase의 S3 호환 엔드포인트에 직접 붙는다(공식 문서: docs/guides/
  storage/s3/authentication). 인증은 PC1에 로컬로 저장된 AWS CLI 프로필만
  사용하며, 이 스크립트/저장소 어디에도 Secret을 담지 않는다.

  NOMPASS와 완전히 분리하기 위해 이 스크립트는:
    - 기본 버킷을 `space-shift-releases`로 쓴다(NOMPASS는 `app-releases`).
    - version.json에 `app: "space-shift"` 필드를 자동으로 채워 넣는다
      (AppUpdateInfo.fromJson이 이 값이 아니면 절대 파싱하지 않는다).
    - ProjectRef/AwsProfile을 하드코딩된 기본값 없이 **필수 파라미터**로
      요구한다 — 실수로 다른 프로젝트(예: NOMPASS 계정)에 잘못 배포하는
      일을 막기 위함이다. 최초 1회는 사용자가 SPACE SHIFT 전용 Supabase
      프로젝트/버킷/AWS 프로필을 정하고 `aws configure --profile <이름>`을
      끝내둔 뒤 그 값을 파라미터로 넘겨야 한다.

  실행 전 반드시 확인한다:
    - APK 실제 존재
    - APK 실제 versionCode/versionName(aapt dump badging으로 직접 측정 —
      암산하지 않는다)
    - 새 versionCode가 현재 라이브 versionCode보다 큼(역행 금지)

  version.json은 이 스크립트가 자동으로 만든다(수동 작성 불필요) —
  versionName/versionCode는 항상 APK 실측값을 그대로 쓰므로 값이 어긋날
  수 없다.

  업로드는 항상 APK 먼저, version.json 마지막(Tab이 새 version.json을
  먼저 읽었는데 APK가 아직 없는 상태를 방지).

.PARAMETER ApkPath
  업로드할 release APK의 전체 경로.

.PARAMETER ProjectRef
  Supabase 프로젝트 ref. NOMPASS와 **같은** 프로젝트를 공유해서 쓰기로
  확정되었으므로 기본값을 그 프로젝트로 둔다 — 대신 버킷 이름(항상
  `space-shift-releases`, 아래 코드 레벨 allowlist로 강제)과 `version.json`의
  `app` 필드로 격리한다. 이 값이 예상 프로젝트와 다르면 즉시 FAIL한다(다른
  프로젝트로 잘못 배포되는 사고 방지).

.PARAMETER AwsProfile
  이 배포에 사용할 AWS CLI 프로필 이름(NOMPASS와 같은 프로젝트를 공유하는
  것으로 확정되었으므로 기존 `nompass-storage` 프로필 재사용을 허용한다 —
  단, 이 스크립트는 코드 레벨 allowlist로 `space-shift-releases` 버킷
  외에는 그 어떤 자격증명으로도 절대 쓰기 요청을 보내지 않는다).

.PARAMETER Region
  Supabase 프로젝트의 Storage 리전. 기본값 ap-northeast-2.

.PARAMETER ReleaseNotes
  version.json에 담을 간단한 릴리스 노트(선택).

.EXAMPLE
  .\tool\publish_android_update.ps1 `
    -ApkPath "C:\ASON\SPACE_SHIFT_TAB_APK\SPACE_SHIFT_V1_MASTER_TAB_E2E_vc9.apk" `
    -AwsProfile "nompass-storage"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ApkPath,

    [string]$ProjectRef = "mljvgngjmrvoqjwvvyeg",

    [Parameter(Mandatory = $true)]
    [string]$AwsProfile,

    [string]$Region = "ap-northeast-2",

    [string]$ReleaseNotes = ""
)

$ErrorActionPreference = "Stop"

# ── 격리 상수 (코드 레벨 allowlist) ─────────────────────────────────────────
# SPACE SHIFT는 이 프로젝트 안에서 이 버킷 하나만 쓴다. -Bucket 파라미터를
# 아예 두지 않는다 — 파라미터로 노출하면 실수/오타로 다른 버킷(예:
# NOMPASS의 app-releases)을 넘길 수 있기 때문이다. 이 값은 스크립트
# 코드에서만 바꿀 수 있고, 모든 S3 쓰기 함수는 실행 직전에 이 값과
# 정확히 같은지 다시 검증한다(방어적 이중 확인).
$ExpectedProjectRef = "mljvgngjmrvoqjwvvyeg"
$AllowedBucket = "space-shift-releases"
$ForbiddenBuckets = @("app-releases", "project-documents")
$Bucket = $AllowedBucket

# AWS CLI v2 기본 체크섬 헤더는 Supabase S3 게이트웨이가 지원하지 않아 빈 오류로
# 실패할 수 있다 — 공식 AWS CLI 환경변수로 완화(비공식 우회 아님).
$env:AWS_REQUEST_CHECKSUM_CALCULATION = "WHEN_REQUIRED"
$env:AWS_RESPONSE_CHECKSUM_VALIDATION = "WHEN_REQUIRED"

$SupabaseUrl = "https://$ProjectRef.supabase.co"
$S3Endpoint = "https://$ProjectRef.storage.supabase.co/storage/v1/s3"
$AppId = "space-shift"

function Write-Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Write-Ok($msg) { Write-Host "OK: $msg" -ForegroundColor Green }
function Write-Fail($msg) { Write-Host "FAIL: $msg" -ForegroundColor Red }

function Abort($msg) {
    Write-Fail $msg
    Write-Host "`nSPACE SHIFT ANDROID DEPLOY: FAIL" -ForegroundColor Red
    exit 1
}

function Assert-AllowedDestination($dst) {
    # 코드 레벨 allowlist — 이 함수를 거치지 않고는 어떤 S3 쓰기도 실행되지
    # 않는다. NOMPASS의 app-releases/project-documents를 포함해
    # space-shift-releases가 아닌 목적지는 절대 통과하지 못한다.
    if ($dst -notmatch "^s3://$([regex]::Escape($AllowedBucket))/") {
        Abort "안전장치 발동: 허용되지 않은 목적지에 쓰기를 시도함: $dst (허용된 버킷은 '$AllowedBucket' 뿐)"
    }
    foreach ($forbidden in $ForbiddenBuckets) {
        if ($dst -match "^s3://$([regex]::Escape($forbidden))/") {
            Abort "안전장치 발동: 금지된 버킷('$forbidden', NOMPASS 소유)에 쓰기를 시도함: $dst"
        }
    }
}

function Invoke-S3Cp($src, $dst, $contentType) {
    Assert-AllowedDestination $dst
    # 네이티브 exe의 stderr를 2>&1로 리다이렉트하면 Windows PowerShell 5.1이
    # 이를 NativeCommandError로 감싸 $ErrorActionPreference=Stop과 함께
    # 스크립트를 강제 종료시킨다(성공 시에도). stderr는 리다이렉트 없이도
    # 콘솔에 그대로 보이므로, 종료 코드만 $LASTEXITCODE로 확인한다.
    & aws s3 cp $src $dst --content-type $contentType --profile $AwsProfile --endpoint-url $S3Endpoint --region $Region
    return $LASTEXITCODE
}

# ── -1. 격리 안전장치 사전 검증 ─────────────────────────────────────────────
Write-Step "-1. 프로젝트/버킷 격리 사전 검증"
if ($ProjectRef -ne $ExpectedProjectRef) {
    Abort "ProjectRef('$ProjectRef')가 예상 프로젝트('$ExpectedProjectRef')와 다름 — 다른 Supabase 프로젝트로 잘못 배포되는 것을 막기 위해 중단함."
}
Write-Ok "ProjectRef 확인: $ProjectRef"
if ($Bucket -ne $AllowedBucket) {
    # $Bucket은 스크립트 내부 상수라 이론상 여기 도달할 수 없지만, 코드가
    # 바뀌어도 안전하도록 이중으로 확인한다.
    Abort "버킷('$Bucket')이 허용된 버킷('$AllowedBucket')과 다름 — 배포 중단."
}
if ($ForbiddenBuckets -contains $Bucket) {
    Abort "버킷('$Bucket')이 NOMPASS 소유 금지 목록에 있음 — 배포 중단."
}
Write-Ok "버킷 확인: $Bucket (NOMPASS 소유 버킷과 격리됨: $($ForbiddenBuckets -join ', '))"

# ── 0. AWS CLI / 인증 확인 ─────────────────────────────────────────────────
Write-Step "0. AWS CLI 및 S3 인증 확인"
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    Abort "AWS CLI를 찾을 수 없음(winget install Amazon.AWSCLI 필요)"
}
& aws s3 ls --profile $AwsProfile --endpoint-url $S3Endpoint --region $Region "s3://$Bucket/" | Out-Host
if ($LASTEXITCODE -ne 0) {
    Abort "S3 인증/읽기 실패 — 'aws configure --profile $AwsProfile'가 이 PC에서 끝났는지, 버킷 '$Bucket'이 실제 존재하는지 확인할 것."
}
Write-Ok "S3 엔드포인트/프로필 인증 정상, $Bucket 버킷 읽기 성공"

# ── 1. APK 존재 확인 ────────────────────────────────────────────────────
Write-Step "1. APK 파일 확인"
if (-not (Test-Path $ApkPath)) { Abort "APK 파일을 찾을 수 없음: $ApkPath" }
Write-Ok "APK: $ApkPath"

# ── 2. APK 크기 확인 (프로젝트 전역 오브젝트 크기 제한 50MiB) ─────────────
# 이진 탐색으로 실측 확인함(2026-08-31): 52,428,800 bytes(=50MiB, PowerShell의
# `50MB` 리터럴과 동일)까지는 S3 업로드 성공, 그 이상은 UploadPart/PutObject
# 양쪽 다 빈 오류로 실패. Dashboard UI만의 제한이 아니라 S3 프로토콜에도
# 그대로 적용되는 프로젝트 전역 설정이다 — universal APK(~50.9MB)가 이 벽에
# 걸려 --split-per-abi(arm64 전용, ~18MB)로 전환해 우회했다.
Write-Step "2. APK 크기 확인"
$apkSizeBytes = (Get-Item $ApkPath).Length
$apkSizeMB = [math]::Round($apkSizeBytes / 1MB, 2)
Write-Host "APK 크기: $apkSizeMB MB ($apkSizeBytes bytes)"
if ($apkSizeBytes -gt 50MB) {
    Abort "APK가 50MiB(52,428,800 bytes)를 초과함($apkSizeMB MB) — 프로젝트 전역 파일 크기 제한에 걸림. universal APK 대신 --split-per-abi로 ABI별 APK를 만들 것."
}
Write-Ok "50MiB 제한 이내"

# ── 3. aapt로 실제 versionCode/versionName/applicationId 측정 ─────────────
Write-Step "3. APK 실제 메타데이터 측정 (aapt dump badging)"
$androidHome = $env:ANDROID_HOME
if (-not $androidHome) { $androidHome = "$env:LOCALAPPDATA\Android\sdk" }
$aapt = Get-ChildItem -Path "$androidHome\build-tools" -Filter "aapt.exe" -Recurse -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
if (-not $aapt) { Abort "aapt.exe를 찾을 수 없음(Android SDK build-tools 확인 필요)" }

$badging = & $aapt dump badging $ApkPath 2>&1 | Select-String "^package:"
if (-not $badging) { Abort "aapt dump badging 결과를 읽을 수 없음 — APK가 손상됐을 수 있음" }

if ($badging -match "name='([^']+)'") { $applicationId = $matches[1] } else { Abort "applicationId를 파싱할 수 없음: $badging" }
if ($badging -match "versionCode='(\d+)'") { $actualVersionCode = [int]$matches[1] } else { Abort "versionCode를 파싱할 수 없음: $badging" }
if ($badging -match "versionName='([^']+)'") { $actualVersionName = $matches[1] } else { Abort "versionName을 파싱할 수 없음: $badging" }
Write-Ok "applicationId=$applicationId, versionCode=$actualVersionCode, versionName=$actualVersionName"

if ($applicationId -ne "com.example.ason_space") {
    Abort "applicationId가 SPACE SHIFT($applicationId 예상: com.example.ason_space)와 다름 — 다른 앱의 APK를 잘못 지정했을 수 있음"
}

# ── 4. 라이브 versionCode보다 큰 값인지 확인 (역행 금지) ───────────────────
Write-Step "4. 라이브 versionCode 대비 역행 여부 확인"
try {
    $liveBefore = Invoke-RestMethod -Uri "$SupabaseUrl/storage/v1/object/public/$Bucket/version.json?ts=$(Get-Date -UFormat %s)" -Method Get -ErrorAction Stop
    Write-Host "현재 라이브 versionCode: $($liveBefore.versionCode)"
    if ($actualVersionCode -le [int]$liveBefore.versionCode) {
        Abort "새 versionCode($actualVersionCode)가 라이브 versionCode($($liveBefore.versionCode))보다 크지 않음 — Tab이 업데이트를 감지하지 못함, 배포 중단"
    }
    Write-Ok "$($liveBefore.versionCode) -> $actualVersionCode (역행 아님)"
} catch {
    Write-Host "라이브 version.json이 아직 없거나 조회 실패 — 최초 배포로 간주하고 계속 진행" -ForegroundColor Yellow
}

# ── 5. APK 업로드 (항상 먼저, S3 프로토콜) ─────────────────────────────────
Write-Step "5. APK 업로드"
$apkFileName = Split-Path $ApkPath -Leaf
Invoke-S3Cp $ApkPath "s3://$Bucket/$apkFileName" "application/vnd.android.package-archive"
if ($LASTEXITCODE -ne 0) { Abort "APK 업로드 실패(aws s3 cp 종료 코드 $LASTEXITCODE)" }
Write-Ok "APK 업로드 명령 완료: $apkFileName"

# ── 6. APK 실제 접근/크기 검증 ─────────────────────────────────────────────
# 업로드 직후 CDN 엣지가 아주 짧게 과거 응답을 캐시할 수 있어 짧은 간격으로 재시도한다.
Write-Step "6. APK 공개 URL 접근 검증"
$apkUrl = "$SupabaseUrl/storage/v1/object/public/$Bucket/$apkFileName"
$apkVerified = $false
for ($attempt = 1; $attempt -le 5; $attempt++) {
    try {
        $head = Invoke-WebRequest -Uri "$apkUrl`?ts=$(Get-Date -UFormat %s)" -Method Head -ErrorAction Stop
        $contentLengthHeader = $head.Headers["Content-Length"]
        if ($contentLengthHeader -is [array]) { $contentLengthHeader = $contentLengthHeader[0] }
        $liveApkSize = [int64]$contentLengthHeader
        Write-Host "시도 $attempt/5 — 라이브 APK 크기: $([math]::Round($liveApkSize/1MB,2)) MB"
        if ($liveApkSize -eq $apkSizeBytes) {
            Write-Ok "APK 공개 URL 접근 성공, 크기 일치"
            $apkVerified = $true
            break
        }
        Write-Host "크기 불일치(예상 $apkSizeBytes) — 3초 후 재시도" -ForegroundColor Yellow
        Start-Sleep -Seconds 3
    } catch {
        Write-Host "접근 실패($($_.Exception.Message)) — 3초 후 재시도" -ForegroundColor Yellow
        Start-Sleep -Seconds 3
    }
}
if (-not $apkVerified) {
    Abort "5회 재시도 후에도 라이브 APK 크기가 로컬 파일($apkSizeBytes bytes)과 일치하지 않음 — 업로드가 손상됐을 수 있음"
}

# ── 7. version.json 생성 + 업로드 (반드시 마지막) ─────────────────────────
# versionName/versionCode/apkUrl은 항상 위에서 측정한 APK 실측값 그대로
# 채운다 — 수동 입력이 아니므로 값이 어긋날 수 없다.
Write-Step "7. version.json 생성 및 업로드 (마지막 단계)"
$versionJsonObj = [ordered]@{
    app          = $AppId
    versionName  = $actualVersionName
    versionCode  = $actualVersionCode
    apkUrl       = $apkUrl
    releaseNotes = $ReleaseNotes
}
$tempVersionJsonPath = Join-Path $env:TEMP "space_shift_version_$actualVersionCode.json"
$versionJsonText = $versionJsonObj | ConvertTo-Json -Compress
# Windows PowerShell 5.1의 `Set-Content -Encoding UTF8`은 항상 BOM을 붙인다.
# BOM이 앞에 붙은 JSON은 curl 등에서는 눈에 안 띄지만, Invoke-RestMethod를
# 포함한 일부 JSON 파서가 이를 유효하지 않은 것으로 처리해 모든 필드가
# 빈 값으로 읽힌다(8단계 최종 검증에서 실제로 이 문제가 발생해 확인됨) —
# 그래서 BOM 없는 UTF-8로 직접 써야 한다.
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($tempVersionJsonPath, $versionJsonText, $utf8NoBom)
Write-Host "생성된 version.json: $versionJsonText"

Invoke-S3Cp $tempVersionJsonPath "s3://$Bucket/version.json" "application/json"
if ($LASTEXITCODE -ne 0) { Abort "version.json 업로드 실패(종료 코드 $LASTEXITCODE)" }
Remove-Item $tempVersionJsonPath -Force -ErrorAction SilentlyContinue
Write-Ok "version.json 업로드 명령 완료"

# ── 8. 라이브 재조회 + 최종 검증 (cache-busting) ──────────────────────────
Write-Step "8. 라이브 서버 최종 검증"
Start-Sleep -Seconds 2
try {
    $liveAfter = Invoke-RestMethod -Uri "$SupabaseUrl/storage/v1/object/public/$Bucket/version.json?ts=$(Get-Date -UFormat %s)" -Method Get -ErrorAction Stop
} catch {
    Abort "라이브 version.json 재조회 실패: $($_.Exception.Message)"
}
Write-Host "라이브 응답: app=$($liveAfter.app), versionName=$($liveAfter.versionName), versionCode=$($liveAfter.versionCode)"
if ($liveAfter.app -ne $AppId) { Abort "라이브 version.json의 app 필드('$($liveAfter.app)')가 '$AppId'가 아님" }
if ([int]$liveAfter.versionCode -ne $actualVersionCode) { Abort "라이브 versionCode($($liveAfter.versionCode))가 기대값($actualVersionCode)과 다름" }
if ($liveAfter.versionName -ne $actualVersionName) { Abort "라이브 versionName($($liveAfter.versionName))이 기대값($actualVersionName)과 다름" }
try {
    Invoke-WebRequest -Uri $liveAfter.apkUrl -Method Head -ErrorAction Stop | Out-Null
    Write-Ok "라이브 version.json이 가리키는 APK URL 접근 성공: $($liveAfter.apkUrl)"
} catch {
    Abort "라이브 version.json의 apkUrl 접근 실패: $($liveAfter.apkUrl)"
}

Write-Host "`nSPACE SHIFT ANDROID DEPLOY: PASS" -ForegroundColor Green
Write-Host "versionName=$actualVersionName versionCode=$actualVersionCode apkUrl=$($liveAfter.apkUrl)"
Write-Host "`nGalaxy Tab 빌드 시 --dart-define=SUPABASE_URL=$SupabaseUrl 을 반드시 포함해야 이 채널을 확인합니다."
exit 0





