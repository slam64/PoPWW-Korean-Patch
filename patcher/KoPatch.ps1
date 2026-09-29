<#
  KoPatch.ps1 - 페르시아의 왕자: 전사의 길 (Steam PC판) 한글 패치 / 영상 건너뛰기 설치·제거

  INSTALL.bat / UNINSTALL.bat 이 실행합니다 (Windows 10/11 기본 Windows PowerShell 5.1).
  텍스트 파일이므로 메모장으로 열어 무엇을 하는지 직접 확인할 수 있습니다.

  - 게임이나 모드의 파일을 통째로 담지 않습니다. patcher\data 의 차분(바뀌는 부분)만 적용합니다.
  - 파일마다 SHA-256으로 버전을 확인하고, 모르는 버전이면 아무것도 바꾸지 않고 멈춥니다.
  - 바꾸기 전에 원래 내용을 게임 폴더의 백업 폴더(KoPatch_backup / VideoSkip_backup)에 둡니다.
    UNINSTALL.bat 이 그것으로 되돌립니다.

  powershell -ExecutionPolicy Bypass -File KoPatch.ps1 [-Mode install|uninstall] [-GamePath 경로]
                                                       [-Xbox ask|yes|no] [-Yes] [-NoPause]
#>
param(
    [ValidateSet('install', 'uninstall')] [string] $Mode = 'install',
    [string] $GamePath = '',
    [ValidateSet('ask', 'yes', 'no')] [string] $Xbox = 'ask',
    [switch] $Yes,
    [switch] $NoPause
)

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
$PatcherDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Man = [IO.File]::ReadAllText((Join-Path $PatcherDir 'manifest.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
$script:Lines = New-Object 'System.Collections.Generic.List[string]'
$script:Warnings = 0
$script:Game = $null
$script:BackupDir = $null

# ------------------------------------------------------------------ output

function Say([string]$Text, [string]$Color = 'Gray') {
    Write-Host $Text -ForegroundColor $Color
    $script:Lines.Add($Text)
}

function Warn([string]$Text) {
    $script:Warnings++
    Say ('  ! ' + $Text) 'Yellow'
}

function Ask-YesNo([string]$Question, [bool]$Default) {
    if ($Yes) { return $Default }
    $hint = if ($Default) { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        $a = Read-Host "$Question $hint"
        if ($null -eq $a) { return $Default }
        $a = $a.Trim().ToLowerInvariant()
        if ($a -eq '') { return $Default }
        if ($a -in @('y', 'yes', 'ㅛ', '예', '네')) { return $true }
        if ($a -in @('n', 'no', 'ㅜ', '아니오', '아니요')) { return $false }
    }
}

# ------------------------------------------------------------------ bytes and hashes

function Hex([byte[]]$Bytes) {
    return [BitConverter]::ToString($Bytes).Replace('-', '').ToLowerInvariant()
}

function Sha-Bytes([byte[]]$Bytes) {
    $h = [Security.Cryptography.SHA256]::Create()
    try { return (Hex ($h.ComputeHash($Bytes))) } finally { $h.Dispose() }
}

function Sha-File([string]$Path) {
    $h = [Security.Cryptography.SHA256]::Create()
    $fs = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
    try { return (Hex ($h.ComputeHash($fs))) } finally { $fs.Dispose(); $h.Dispose() }
}

function Slice([byte[]]$Bytes, [int]$Offset, [int]$Count) {
    $r = New-Object byte[] $Count
    [Array]::Copy($Bytes, $Offset, $r, 0, $Count)
    return ,$r
}

function Game-File([string]$Rel) { return (Join-Path $script:Game ($Rel -replace '/', '\')) }
function Backup-File([string]$Dir, [string]$Rel) { return (Join-Path $Dir ($Rel -replace '/', '\')) }
function Show-Rel([string]$Rel) { return ($Rel -replace '/', '\') }

function Clear-ReadOnly([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        $fi = New-Object IO.FileInfo $Path
        if ($fi.IsReadOnly) { $fi.IsReadOnly = $false }
    }
}

function Ensure-Parent([string]$Path) {
    $d = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }
}

function Write-Bytes([string]$Path, [byte[]]$Bytes) {
    Ensure-Parent $Path
    $tmp = $Path + '.kotmp'
    [IO.File]::WriteAllBytes($tmp, $Bytes)
    Clear-ReadOnly $Path
    [IO.File]::Copy($tmp, $Path, $true)
    [IO.File]::Delete($tmp)
}

function Read-Head([string]$Path, [int]$Count) {
    $fs = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
    try {
        $n = [int][Math]::Min([int64]$Count, $fs.Length)
        $buf = New-Object byte[] $n
        $got = 0
        while ($got -lt $n) {
            $r = $fs.Read($buf, $got, $n - $got)
            if ($r -le 0) { break }
            $got += $r
        }
        return @{ Bytes = $buf; Length = $fs.Length }
    } finally { $fs.Dispose() }
}

function Write-Head([string]$Path, [byte[]]$Bytes) {
    Clear-ReadOnly $Path
    $fs = [IO.File]::Open($Path, 'Open', 'ReadWrite', 'None')
    try {
        [void]$fs.Seek(0, 'Begin')
        $fs.Write($Bytes, 0, $Bytes.Length)
        $fs.Flush($true)
    } finally { $fs.Dispose() }
}

# ------------------------------------------------------------------ patch formats

# KPD1: COPY/ADD delta.  u32 source size, u32 target size, u32 op count; op 0 = COPY u32 offset, u32 length;
# op 1 = ADD u32 length + bytes.
function Apply-Kpd([byte[]]$Src, [string]$PatchRel) {
    $p = [IO.File]::ReadAllBytes((Join-Path $PatcherDir ($PatchRel -replace '/', '\')))
    $br = New-Object IO.BinaryReader ([IO.MemoryStream]::new($p))
    if ([Text.Encoding]::ASCII.GetString($br.ReadBytes(4)) -ne 'KPD1') { throw "손상된 차분 파일: $PatchRel" }
    $srcLen = [int]$br.ReadUInt32()
    $dstLen = [int]$br.ReadUInt32()
    $n = [int]$br.ReadUInt32()
    if ($Src.Length -ne $srcLen) { throw "차분의 원본 크기가 맞지 않음: $PatchRel" }
    $out = New-Object byte[] $dstLen
    $pos = 0
    for ($k = 0; $k -lt $n; $k++) {
        $t = $br.ReadByte()
        if ($t -eq 0) {
            $off = [int]$br.ReadUInt32()
            $len = [int]$br.ReadUInt32()
            [Array]::Copy($Src, $off, $out, $pos, $len)
        } else {
            $len = [int]$br.ReadUInt32()
            $chunk = $br.ReadBytes($len)
            [Array]::Copy($chunk, 0, $out, $pos, $len)
        }
        $pos += $len
    }
    if ($pos -ne $dstLen) { throw "손상된 차분 파일: $PatchRel" }
    return ,$out
}

# KPR1: in-place byte ranges.  u64 file size, u32 range count; range = u64 offset, u32 length + bytes.
function Read-Kpr([string]$Path) {
    $p = [IO.File]::ReadAllBytes($Path)
    $br = New-Object IO.BinaryReader ([IO.MemoryStream]::new($p))
    if ([Text.Encoding]::ASCII.GetString($br.ReadBytes(4)) -ne 'KPR1') { throw "손상된 차분 파일: $Path" }
    $size = [int64]$br.ReadUInt64()
    $n = [int]$br.ReadUInt32()
    $offs = New-Object 'int64[]' $n
    $lens = New-Object 'int32[]' $n
    $at = New-Object 'int32[]' $n
    $total = 0
    for ($k = 0; $k -lt $n; $k++) {
        $offs[$k] = [int64]$br.ReadUInt64()
        $lens[$k] = [int]$br.ReadUInt32()
        $at[$k] = [int]$br.BaseStream.Position
        [void]$br.BaseStream.Seek($lens[$k], 'Current')
        $total += $lens[$k]
    }
    if ($br.BaseStream.Position -ne $p.Length) { throw "손상된 차분 파일: $Path" }
    return [pscustomobject]@{ Bytes = $p; Size = $size; Count = $n; Offs = $offs; Lens = $lens; At = $at; Total = $total }
}

function Read-Ranges([string]$Path, $Kpr) {
    $data = New-Object byte[] $Kpr.Total
    $fs = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
    try {
        $pos = 0
        for ($k = 0; $k -lt $Kpr.Count; $k++) {
            [void]$fs.Seek($Kpr.Offs[$k], 'Begin')
            $need = $Kpr.Lens[$k]
            $got = 0
            while ($got -lt $need) {
                $r = $fs.Read($data, $pos + $got, $need - $got)
                if ($r -le 0) { throw "파일이 예상보다 짧습니다: $Path" }
                $got += $r
            }
            $pos += $need
        }
    } finally { $fs.Dispose() }
    return ,$data
}

function Write-Ranges([string]$Path, $Kpr) {
    Clear-ReadOnly $Path
    $fs = [IO.File]::Open($Path, 'Open', 'ReadWrite', 'None')
    try {
        for ($k = 0; $k -lt $Kpr.Count; $k++) {
            [void]$fs.Seek($Kpr.Offs[$k], 'Begin')
            $fs.Write($Kpr.Bytes, $Kpr.At[$k], $Kpr.Lens[$k])
        }
        $fs.Flush($true)
    } finally { $fs.Dispose() }
}

function Save-KprBackup([string]$Path, $Kpr, [byte[]]$Data) {
    $ms = New-Object IO.MemoryStream
    $bw = New-Object IO.BinaryWriter $ms
    $bw.Write([Text.Encoding]::ASCII.GetBytes('KPR1'))
    $bw.Write([uint64]$Kpr.Size)
    $bw.Write([uint32]$Kpr.Count)
    $pos = 0
    for ($k = 0; $k -lt $Kpr.Count; $k++) {
        $bw.Write([uint64]$Kpr.Offs[$k])
        $bw.Write([uint32]$Kpr.Lens[$k])
        $bw.Write($Data, $pos, $Kpr.Lens[$k])
        $pos += $Kpr.Lens[$k]
    }
    $bw.Flush()
    Write-Bytes $Path $ms.ToArray()
}

function Get-RangesState([string]$Path, $Kpr, $Spec) {
    if ((New-Object IO.FileInfo $Path).Length -ne $Kpr.Size) { return @{ State = 'size'; Data = $null } }
    $cur = Read-Ranges $Path $Kpr
    $s = Sha-Bytes $cur
    if ($s -eq $Spec.new_sha) { return @{ State = 'new'; Data = $cur } }
    if ($s -eq $Spec.old_sha) { return @{ State = 'old'; Data = $cur } }
    return @{ State = 'other'; Data = $cur }
}

# ------------------------------------------------------------------ exe (Large Address Aware bit kept as found)

function Set-Laa([byte[]]$Bytes, [int]$ChOff, [bool]$On) {
    $v = [int][BitConverter]::ToUInt16($Bytes, $ChOff)
    $v = if ($On) { $v -bor 0x20 } else { $v -band 0xFFDF }
    $Bytes[$ChOff] = [byte]($v -band 0xFF)
    $Bytes[$ChOff + 1] = [byte](($v -shr 8) -band 0xFF)
}

function Get-ExeInfo([string]$Path) {
    $b = [IO.File]::ReadAllBytes($Path)
    $pe = [BitConverter]::ToInt32($b, 0x3C)
    $chOff = $pe + 0x16
    $ckOff = $pe + 0x58
    $laa = (([int][BitConverter]::ToUInt16($b, $chOff)) -band 0x20) -ne 0
    $n = [byte[]]$b.Clone()
    Set-Laa $n $chOff $false
    for ($i = 0; $i -lt 4; $i++) { $n[$ckOff + $i] = 0 }
    return [pscustomobject]@{ Bytes = $b; Sha = (Sha-Bytes $b); NormSha = (Sha-Bytes $n); Laa = $laa; ChOff = $chOff; CkOff = $ckOff }
}

function Build-Exe($Info, $Spec, [bool]$ForceLaa = $false) {
    $src = [byte[]]$Info.Bytes.Clone()
    Set-Laa $src $Info.ChOff $false
    $ck = [BitConverter]::GetBytes([uint32]$Spec.stock_checksum)
    [Array]::Copy($ck, 0, $src, $Info.CkOff, 4)
    if ((Sha-Bytes $src) -ne $Spec.stock_sha) { throw 'EXE를 원본으로 맞추지 못했습니다' }
    $out = Apply-Kpd $src $Spec.patch
    $laa = $Info.Laa -or $ForceLaa
    if ($laa) { Set-Laa $out $Info.ChOff $true }
    $want = if ($laa) { $Spec.target_laa_sha } else { $Spec.target_sha }
    if ((Sha-Bytes $out) -ne $want) { throw 'EXE 패치 결과가 예상과 다릅니다' }
    return ,$out
}

# ------------------------------------------------------------------ Evgesha.JK (4K Texture Pack) overlay index

function Test-Intersects($Kpr, [int64]$Start, [int64]$End) {
    $i = [Array]::BinarySearch($Kpr.Offs, $End)
    if ($i -lt 0) { $i = -bnot $i }
    $j = $i - 1
    if ($j -lt 0) { return $false }
    return (($Kpr.Offs[$j] + $Kpr.Lens[$j]) -gt $Start)
}

function Get-JkPlan([string]$Path, $Kpr) {
    $jk = $Man.jk
    $h = Read-Head $Path ([int]$jk.head_bytes)
    $b = $h.Bytes
    if ($b.Length -lt 0x90 -or [Text.Encoding]::ASCII.GetString($b, 0, 8) -ne "EVGJK1`r`n") {
        return @{ State = 'bad'; Why = 'Evgesha.JK 형식이 아닙니다' }
    }
    $ver = [BitConverter]::ToUInt32($b, 8); $hsize = [BitConverter]::ToUInt32($b, 12)
    $tsz = [BitConverter]::ToUInt32($b, 16); $osz = [BitConverter]::ToUInt32($b, 20)
    $ntex = [int64][BitConverter]::ToUInt32($b, 24); $nov = [int64][BitConverter]::ToUInt32($b, 28)
    $bfsize = [BitConverter]::ToInt64($b, 0x28); $toff = [BitConverter]::ToInt64($b, 0x30)
    $ooff = [BitConverter]::ToInt64($b, 0x38); $pstart = [BitConverter]::ToInt64($b, 0x40)
    $pbytes = [BitConverter]::ToInt64($b, 0x48)
    if ($ver -ne 1 -or $hsize -ne 0x90 -or $tsz -ne 0x68 -or $osz -ne 0x60 -or $toff -ne 0x90 -or $ooff -ne ($toff + $ntex * 0x68)) {
        return @{ State = 'bad'; Why = '알 수 없는 Evgesha.JK 형식' }
    }
    $oend = $ooff + $nov * 0x60
    if (($pstart + $pbytes) -ne $h.Length -or $oend -gt $pstart -or $oend -gt $b.Length) {
        return @{ State = 'bad'; Why = 'Evgesha.JK 크기가 목록과 맞지 않습니다 (다운로드가 덜 됐거나 손상)' }
    }
    if ($bfsize -ne $Kpr.Size) { return @{ State = 'bad'; Why = '이 4K 팩은 다른 prince.bf를 대상으로 만들어졌습니다' } }
    $sha = [Security.Cryptography.SHA256]::Create()
    [void]$sha.TransformBlock($b, [int]$toff, [int]($ntex * 0x68), $null, 0)
    [void]$sha.TransformFinalBlock($b, [int]$ooff, [int]($nov * 0x60))
    $idx = Hex $sha.Hash
    $sha.Dispose()
    if ($idx -ne (Hex (Slice $b 0x70 32))) { return @{ State = 'bad'; Why = 'Evgesha.JK 목록 해시가 맞지 않습니다' } }

    $known = @{}
    foreach ($d in @($jk.drop)) { $known[([string]$d.record).ToLowerInvariant()] = [string]$d.world }
    $drop = New-Object 'System.Collections.Generic.List[int]'
    $worlds = New-Object 'System.Collections.Generic.List[string]'
    $unknown = New-Object 'System.Collections.Generic.List[string]'
    for ($i = 0; $i -lt $nov; $i++) {
        $o = [int]($ooff + $i * 0x60)
        $bfo = [BitConverter]::ToInt64($b, $o + 8)
        $ln = [BitConverter]::ToInt64($b, $o + 24)
        if (Test-Intersects $Kpr $bfo ($bfo + $ln)) {
            $rec = Hex (Slice $b $o 0x60)
            if ($known.ContainsKey($rec)) { $drop.Add($i); $worlds.Add($known[$rec]) }
            else { $unknown.Add(('{0:X8}' -f [BitConverter]::ToUInt32($b, $o))) }
        }
    }
    if ($unknown.Count) { return @{ State = 'unknown'; Why = ('한글 패치가 바꾸는 곳을 덮는 알 수 없는 항목: ' + ($unknown -join ', ')) } }
    if ($drop.Count -eq 0) { return @{ State = 'done'; Nov = $nov } }

    $new = [byte[]]$b.Clone()
    $kept = New-Object IO.MemoryStream
    for ($i = 0; $i -lt $nov; $i++) {
        if (-not $drop.Contains($i)) { $kept.Write($b, [int]($ooff + $i * 0x60), 0x60) }
    }
    $keptBytes = $kept.ToArray()
    [Array]::Clear($new, [int]$ooff, [int]($nov * 0x60))
    [Array]::Copy($keptBytes, 0, $new, [int]$ooff, $keptBytes.Length)
    $cnt = [BitConverter]::GetBytes([uint32]($nov - $drop.Count))
    [Array]::Copy($cnt, 0, $new, 0x1C, 4)
    $sha = [Security.Cryptography.SHA256]::Create()
    [void]$sha.TransformBlock($b, [int]$toff, [int]($ntex * 0x68), $null, 0)
    [void]$sha.TransformFinalBlock($keptBytes, 0, $keptBytes.Length)
    [Array]::Copy($sha.Hash, 0, $new, 0x70, 32)
    $sha.Dispose()
    return @{ State = 'patch'; Orig = $b; New = $new; Nov = $nov; Keep = ($nov - $drop.Count); Worlds = ($worlds -join ', ') }
}

# ------------------------------------------------------------------ backup state (state.json in the backup folder)

function Load-State([string]$Dir) {
    $files = [ordered]@{}
    $p = Join-Path $Dir 'state.json'
    $product = $null
    $version = $null
    if (Test-Path -LiteralPath $p) {
        $o = [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $product = $o.product
        $version = $o.version
        foreach ($f in @($o.files)) { if ($null -ne $f) { $files[[string]$f.path] = $f } }
    }
    return [pscustomobject]@{ Dir = $Dir; Path = $p; Product = $product; Version = $version; Files = $files }
}

function Save-State($St) {
    $obj = [ordered]@{ product = $Man.product; version = $Man.version; updated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                       files = @($St.Files.Values) }
    Write-Bytes $St.Path ([Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Depth 6)))
}

function Set-Entry($St, [hashtable]$Entry) {
    $St.Files[[string]$Entry.path] = [pscustomobject]$Entry
    Save-State $St
}

function Get-Entry($St, [string]$Rel) {
    if ($St.Files.Contains($Rel)) { return $St.Files[$Rel] }
    return $null
}

function Has-Prop($Obj, [string]$Name) { return ($null -ne $Obj -and $null -ne $Obj.PSObject.Properties[$Name]) }

# ------------------------------------------------------------------ restore (uninstall)

function Restore-Entry($St, $E) {
    $rel = [string]$E.path
    $p = Game-File $rel
    $b = if (Has-Prop $E 'backup') { Backup-File $St.Dir ([string]$E.backup) } else { $null }
    switch ([string]$E.method) {
        'ranges' {
            if (-not (Test-Path -LiteralPath $p)) { Warn "$(Show-Rel $rel) 이(가) 없어 되돌리지 못했습니다"; return $false }
            $bk = Read-Kpr $b
            if ((New-Object IO.FileInfo $p).Length -ne $bk.Size) { Warn "$(Show-Rel $rel) 크기가 달라져 되돌리지 않았습니다"; return $false }
            if ((Sha-Bytes (Read-Ranges $p $bk)) -eq $E.old_sha) { Say "  그대로  $(Show-Rel $rel) (이미 원래 내용)"; return $true }
            Write-Ranges $p $bk
            if ((Sha-Bytes (Read-Ranges $p $bk)) -ne $E.old_sha) { throw "$(Show-Rel $rel) 복구 확인 실패" }
            Say "  복구    $(Show-Rel $rel)" 'Green'
            return $true
        }
        'copy' {
            $cur = if (Test-Path -LiteralPath $p) { Sha-File $p } else { '' }
            if ($cur -eq $E.orig_sha) { Say "  그대로  $(Show-Rel $rel) (이미 원래 파일)"; return $true }
            if ($cur -ne '' -and $cur -ne $E.new_sha) {
                Say "  그대로  $(Show-Rel $rel) (설치 뒤 다른 파일로 바뀌어 있어 건드리지 않음)"
                return $true
            }
            $bytes = [IO.File]::ReadAllBytes($b)
            if ((Sha-Bytes $bytes) -ne $E.orig_sha) { throw "백업 파일이 손상되었습니다: $b" }
            Write-Bytes $p $bytes
            Say "  복구    $(Show-Rel $rel)" 'Green'
            return $true
        }
        'moved' {
            if (-not (Test-Path -LiteralPath $b)) { Warn "백업 폴더에 $(Show-Rel $rel) 이(가) 없습니다"; return $false }
            if (Test-Path -LiteralPath $p) {
                if ((Sha-File $p) -eq (Sha-File $b)) {
                    Remove-Item -LiteralPath $b -Force
                    Say "  그대로  $(Show-Rel $rel) (같은 파일이 이미 있음)"
                    return $true
                }
                Warn "$(Show-Rel $rel) 자리에 다른 파일이 있어, 원래 파일은 백업 폴더에 남겨 둡니다: $b"
                return $false
            }
            Ensure-Parent $p
            Move-Item -LiteralPath $b -Destination $p
            Say "  복구    $(Show-Rel $rel)" 'Green'
            return $true
        }
        'created' {
            if (Test-Path -LiteralPath $p) {
                if ((Sha-File $p) -eq $E.new_sha) {
                    Clear-ReadOnly $p
                    Remove-Item -LiteralPath $p -Force
                    Say "  삭제    $(Show-Rel $rel)" 'Green'
                } else {
                    Say "  그대로  $(Show-Rel $rel) (설치 뒤 바뀐 파일이라 남겨 둠)"
                }
            }
            return $true
        }
        'jkhead' {
            if (-not (Test-Path -LiteralPath $p)) { Say "  그대로  $(Show-Rel $rel) (파일이 없음)"; return $true }
            $cur = Sha-Bytes ((Read-Head $p ([int]$E.head_bytes)).Bytes)
            if ($cur -eq $E.orig_sha) { Say "  그대로  $(Show-Rel $rel) (이미 원래 목록)"; return $true }
            if ($cur -ne $E.new_sha) {
                Say "  그대로  $(Show-Rel $rel) (설치 뒤 팩이 바뀌어 있어 건드리지 않음)"
                return $true
            }
            $orig = [IO.File]::ReadAllBytes($b)
            if ((Sha-Bytes $orig) -ne $E.orig_sha) { throw "백업 파일이 손상되었습니다: $b" }
            Write-Head $p $orig
            if ((Sha-Bytes ((Read-Head $p $orig.Length).Bytes)) -ne $E.orig_sha) { throw "$(Show-Rel $rel) 복구 확인 실패" }
            Say "  복구    $(Show-Rel $rel) (4K 팩 목록 원래대로)" 'Green'
            return $true
        }
    }
    Warn "알 수 없는 백업 항목: $rel"
    return $false
}

function Restore-All($St) {
    $ok = $true
    $entries = @($St.Files.Values)
    [array]::Reverse($entries)
    foreach ($e in $entries) {
        try {
            if (-not (Restore-Entry $St $e)) { $ok = $false }
        } catch {
            Warn ("$(Show-Rel ([string]$e.path)) 되돌리기 실패: " + $_.Exception.Message)
            $ok = $false
        }
    }
    return $ok
}

# ------------------------------------------------------------------ finding the game

function Test-Game([string]$Dir) {
    if (-not $Dir) { return $false }
    return ((Test-Path -LiteralPath (Join-Path $Dir 'POP2.EXE')) -and (Test-Path -LiteralPath (Join-Path $Dir 'prince.bf')))
}

function Find-Game {
    if ($GamePath) {
        $g = $GamePath.Trim().Trim('"').TrimEnd('\')
        if (Test-Game $g) { return (Resolve-Path -LiteralPath $g).Path.TrimEnd('\') }
        throw "지정한 폴더에 POP2.EXE와 prince.bf가 없습니다: $g"
    }
    $d = Split-Path -Parent $PatcherDir
    for ($i = 0; $i -lt 3 -and $d; $i++) {
        if (Test-Game $d) { return $d.TrimEnd('\') }
        $d = Split-Path -Parent $d
    }
    $roots = New-Object 'System.Collections.Generic.List[string]'
    foreach ($key in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
        $v = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        foreach ($prop in 'SteamPath', 'InstallPath') {
            if (Has-Prop $v $prop) { $roots.Add((([string]$v.$prop) -replace '/', '\')) }
        }
    }
    $libs = New-Object 'System.Collections.Generic.List[string]'
    foreach ($s in $roots) {
        $libs.Add($s)
        $vdf = Join-Path $s 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            foreach ($m in [regex]::Matches([IO.File]::ReadAllText($vdf), '"path"\s+"([^"]+)"')) {
                $libs.Add(($m.Groups[1].Value -replace '\\\\', '\'))
            }
        }
    }
    foreach ($l in ($libs | Select-Object -Unique)) {
        $g = Join-Path $l 'steamapps\common\Prince of Persia The Warrior Within'
        if (Test-Game $g) { return $g.TrimEnd('\') }
    }
    Say '게임 폴더를 자동으로 찾지 못했습니다. 폴더를 고르는 창에서 POP2.EXE가 있는 폴더를 골라 주세요.' 'Yellow'
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = '페르시아의 왕자: 전사의 길 게임 폴더(POP2.EXE가 있는 폴더)를 골라 주세요'
    $dlg.ShowNewFolderButton = $false
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and (Test-Game $dlg.SelectedPath)) {
        return $dlg.SelectedPath.TrimEnd('\')
    }
    throw '게임 폴더를 찾지 못했습니다. INSTALL.bat을 게임 폴더(POP2.EXE가 있는 곳) 안에 풀어 실행해 보세요.'
}

function Assert-NotRunning {
    $names = @('POP2', 'POP2WW', 'PrinceOfPersia')
    $run = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $names -contains $_.ProcessName })
    if ($run.Count) {
        throw ('게임이 실행 중입니다 (' + (($run | ForEach-Object { $_.ProcessName + '.exe' }) -join ', ') + '). 게임을 완전히 끈 뒤 다시 실행해 주세요.')
    }
}

function Test-Writable([string]$Dir) {
    try {
        $t = Join-Path $Dir ('.kopatch_' + [guid]::NewGuid().ToString('N'))
        [IO.File]::WriteAllBytes($t, [byte[]]@(0))
        [IO.File]::Delete($t)
        return $true
    } catch { return $false }
}

function Restart-Elevated {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'), '-Mode', $Mode,
                 '-GamePath', ('"' + $script:Game + '"'), '-Xbox', $Xbox)
    if ($Yes) { $argList += '-Yes' }
    if ($NoPause) { $argList += '-NoPause' }
    Say '게임 폴더에 쓸 권한이 없어 관리자 권한으로 다시 실행합니다. (사용자 계정 컨트롤 창에서 [예])' 'Yellow'
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList
}

# ------------------------------------------------------------------ install

function Plan-Item([string]$Rel, [string]$Action, [string]$Note) {
    return @{ Rel = $Rel; Action = $Action; Note = $Note; Data = $null; Info = $null; Bytes = $null; Spec = $null
              Jk = $null; Restore = $false; ForceLaa = $false; Text = $null }
}

function Install-Patch {
    $st = Load-State $script:BackupDir
    $isKorean = $Man.product -eq 'korean'

    # an earlier version of this package: back to the original files first, then this version from scratch
    if ($st.Files.Count -gt 0 -and [string]$st.Version -ne [string]$Man.version) {
        Say "이전 버전(v$($st.Version))이 설치되어 있습니다. 먼저 원래 파일로 되돌린 뒤 v$($Man.version)을 설치합니다." 'Cyan'
        if (-not (Ask-YesNo "이전 버전을 되돌리고 v$($Man.version)을 설치할까요?" $true)) { throw '설치를 취소했습니다.' }
        if (-not (Restore-All $st)) { throw '이전 버전을 되돌리지 못했습니다. 위의 내용을 확인해 주세요 (백업 폴더는 그대로 두었습니다).' }
        Remove-Item -LiteralPath $script:BackupDir -Recurse -Force
        $st = Load-State $script:BackupDir
        Say ''
    }

    # the other package of this pair first (the Korean patch already contains the video skip)
    foreach ($other in @($Man.other_backup_dirs)) {
        $od = Join-Path $script:Game $other
        if (-not (Test-Path -LiteralPath (Join-Path $od 'state.json'))) { continue }
        if (-not $isKorean) {
            throw '한글 패치가 설치되어 있습니다. 한글 패치에는 영상 건너뛰기가 이미 들어 있으니 이 모드는 따로 설치하지 않아도 됩니다.'
        }
        Say '영상 건너뛰기 단독판이 설치되어 있습니다. 한글 패치에 같은 기능이 들어 있으므로 먼저 원래 EXE로 되돌립니다.' 'Cyan'
        if (-not (Ask-YesNo '영상 건너뛰기 단독판을 제거하고 계속할까요?' $true)) { throw '설치를 취소했습니다.' }
        if (-not (Restore-All (Load-State $od))) { throw '영상 건너뛰기 단독판을 되돌리지 못했습니다. 그 모드의 UNINSTALL.bat을 먼저 실행해 주세요.' }
        Remove-Item -LiteralPath $od -Recurse -Force
    }

    $hasAsi = Test-Path -LiteralPath (Game-File 'BinkW32Hooked.DLL')
    $hasXidi = (Test-Path -LiteralPath (Game-File 'dinput8.dll')) -and (Test-Path -LiteralPath (Game-File 'Xidi.ini'))
    $hasPack = (Test-Path -LiteralPath (Game-File 'Evgesha.JK')) -and (Test-Path -LiteralPath (Game-File 'd3d9.dll'))
    $found = @()
    if (Test-Path -LiteralPath (Game-File 'POP2WW.EXE')) { $found += 'Fix 모음 (POP2WW.EXE' + $(if ($hasAsi) { ', ASI 로더' } else { '' }) + $(if ($hasXidi) { ', Xidi' } else { '' }) + ')' }
    if ($hasPack) { $found += '4K 텍스처 팩' }
    Say ('찾은 모드: ' + $(if ($found.Count) { $found -join ' / ' } else { '없음' }))
    Say ''

    $plan = New-Object 'System.Collections.Generic.List[hashtable]'
    $kpr = $null
    $bfSpec = $null
    if ($isKorean) {
        # prince.bf
        $bfSpec = $Man.files.'prince.bf'
        $kpr = Read-Kpr (Join-Path $PatcherDir ($bfSpec.patch -replace '/', '\'))
        $rs = Get-RangesState (Game-File 'prince.bf') $kpr $bfSpec
        switch ($rs.State) {
            'new' { $plan.Add((Plan-Item 'prince.bf' 'done' '한글 (설치되어 있음)')) }
            'old' { $i = Plan-Item 'prince.bf' 'ranges' '원본 → 한글'; $i.Data = $rs.Data; $plan.Add($i) }
            'size' { throw 'prince.bf 크기가 Steam 원본과 다릅니다. Steam에서 "게임 파일 무결성 검사"를 한 뒤 다시 실행해 주세요.' }
            default { throw 'prince.bf가 Steam 원본과 다른 곳이 있어 패치할 수 없습니다. 다른 모드(텍스처·번역 등)가 prince.bf를 고쳤을 수 있습니다. Steam에서 "게임 파일 무결성 검사"를 한 뒤 다시 실행해 주세요.' }
        }

        # update\prince.bf (Fix Compilation: stock + a texture fix, read instead of the root file by its ASI loader)
        $ub = Game-File 'update/prince.bf'
        $ubEntry = Get-Entry $st 'update/prince.bf'
        if (-not (Test-Path -LiteralPath $ub) -and -not $hasPack -and $null -ne $ubEntry -and $ubEntry.method -eq 'moved') {
            $plan.Add((Plan-Item 'update/prince.bf' 'bringback' 'Fix 파일을 백업 폴더에서 되돌린 뒤 → 한글'))
        } elseif (Test-Path -LiteralPath $ub) {
            $us = Get-RangesState $ub $kpr $bfSpec
            if ($hasPack) {
                $i = Plan-Item 'update/prince.bf' 'move' 'Fix 파일 → 백업 폴더로 옮김 (4K 팩이 같은 수정을 적용함)'
                $i.Restore = ($us.State -eq 'new' -and $null -ne $ubEntry -and $ubEntry.method -eq 'ranges')
                $plan.Add($i)
            } elseif ($us.State -eq 'new') {
                $plan.Add((Plan-Item 'update/prince.bf' 'done' '한글 + Fix (설치되어 있음)'))
            } elseif ($us.State -eq 'old') {
                $i = Plan-Item 'update/prince.bf' 'ranges' 'Fix 파일 → 한글 + Fix'
                $i.Data = $us.Data
                $plan.Add($i)
            } else {
                $plan.Add((Plan-Item 'update/prince.bf' 'move' '알 수 없는 파일 → 백업 폴더로 옮김 (한글을 가리므로)'))
            }
        }
    }

    # The Unofficial Patch 2.1 (Dawid Freeman) finds the game as the module "POP2.exe": with the Fix Compilation
    # (its ASI loader BinkW32.DLL loads scripts\*.asi) the Fix launcher is pointed at POP2.EXE (Korean + LAA,
    # what launcher.json's "patch": {"LAA": true} asks for anyway) instead of its POP2WW.EXE copy.
    $uo = $null
    $useUnofficial = $false
    $launcher = Game-File 'launcher.json'
    $launcherText = $null
    if ($isKorean -and (Has-Prop $Man.files 'unofficial') -and $hasAsi -and (Test-Path -LiteralPath $launcher)) {
        $uo = $Man.files.unofficial
        $launcherText = [IO.File]::ReadAllText($launcher)
        if ($launcherText -match '"bin"\s*:\s*"POP2(WW)?\.EXE"') { $useUnofficial = $true }
        else { Warn 'launcher.json의 실행 파일 설정을 알아볼 수 없어 비공식 패치(Unofficial Patch)는 넣지 않습니다.' }
    }

    # exe
    $exeSpec = $Man.files.exe
    foreach ($name in @($exeSpec.names)) {
        $p = Game-File $name
        if (-not (Test-Path -LiteralPath $p)) {
            if ($name -eq 'POP2.EXE') { throw 'POP2.EXE가 없습니다.' }
            continue
        }
        $info = Get-ExeInfo $p
        $what = if ($isKorean) { '한글 + 영상 건너뛰기' } else { '영상 건너뛰기' }
        $forceLaa = ($useUnofficial -and $name -eq 'POP2.EXE')
        if ($forceLaa -and $info.Sha -eq $exeSpec.target_sha) {
            $i = Plan-Item $name 'laa' '한글 → 한글 + 4GB 메모리(LAA) 설정'
            $i.Info = $info
            $plan.Add($i)
        } elseif (($info.Sha -eq $exeSpec.target_sha -and -not $forceLaa) -or $info.Sha -eq $exeSpec.target_laa_sha) {
            $plan.Add((Plan-Item $name 'done' "$what (설치되어 있음)"))
        } elseif ($info.NormSha -eq $exeSpec.stock_norm_sha) {
            $i = Plan-Item $name 'exe' ($(if ($info.Laa) { '원본(LAA) → ' } else { '원본 → ' }) + $what + $(if ($forceLaa -and -not $info.Laa) { ' + 4GB 메모리(LAA) 설정' } else { '' }))
            $i.Info = $info
            $i.ForceLaa = $forceLaa
            $plan.Add($i)
        } elseif (Has-Prop $exeSpec.foreign $info.NormSha) {
            throw "$name 에 '$($exeSpec.foreign.($info.NormSha))'이(가) 설치되어 있습니다. 그것을 먼저 제거(UNINSTALL.bat)한 뒤 다시 실행해 주세요."
        } else {
            throw "$name 이(가) Steam판 원본이 아닙니다 (다른 판이거나 다른 패치가 적용됨). Steam에서 ""게임 파일 무결성 검사""를 한 뒤, Fix 모음을 쓴다면 다시 설치하고 이 설치를 다시 실행해 주세요."
        }
    }

    $wantXbox = $false
    if ($isKorean) {
        # POPData.BF (+ Xbox button names in update\ when the Fix's ASI loader and Xidi are there)
        $pd = $Man.files.popdata
        $pdBytes = [IO.File]::ReadAllBytes((Game-File 'POPData.BF'))
        $pdSha = Sha-Bytes $pdBytes
        if ($pdSha -eq $pd.target_sha -or $pdSha -eq $pd.xbox_sha) {
            $plan.Add((Plan-Item 'POPData.BF' 'done' '한글 (설치되어 있음)'))
        } elseif ($pdSha -eq $pd.stock_sha -or $pdSha -eq $pd.fix_xbox_sha) {
            $i = Plan-Item 'POPData.BF' 'popdata' $(if ($pdSha -eq $pd.stock_sha) { '원본 → 한글' } else { 'Fix의 영어 Xbox판 → 한글' })
            $i.Bytes = $pdBytes
            $plan.Add($i)
        } else {
            throw 'POPData.BF가 Steam 원본이 아닙니다. Steam에서 "게임 파일 무결성 검사"를 한 뒤 다시 실행해 주세요.'
        }
        if ($hasAsi -and $hasXidi) {
            $wantXbox = switch ($Xbox) {
                'yes' { $true }
                'no' { $false }
                default { Ask-YesNo '게임패드 버튼 이름을 Xbox식(A, B, X, Y, LB, RB …)으로 표시할까요? (Fix 모음의 Xidi 사용 시 권장)' $true }
            }
        } elseif ($Xbox -eq 'yes') {
            Warn 'Fix 모음의 ASI 로더·Xidi가 없어 Xbox 버튼 이름은 넣지 않습니다.'
        }
        $up = Game-File 'update/POPData.BF'
        $upEntry = Get-Entry $st 'update/POPData.BF'
        if (Test-Path -LiteralPath $up) {
            $upSha = Sha-File $up
            if ($wantXbox) {
                if ($upSha -eq $pd.xbox_sha) { $plan.Add((Plan-Item 'update/POPData.BF' 'done' '한글 + Xbox 버튼 이름 (설치되어 있음)')) }
                else { $plan.Add((Plan-Item 'update/POPData.BF' 'xbox' '영어판 → 한글 + Xbox 버튼 이름')) }
            } elseif ($hasAsi) {
                if ($upSha -eq $pd.xbox_sha -and $null -ne $upEntry -and $upEntry.method -eq 'created') {
                    $plan.Add((Plan-Item 'update/POPData.BF' 'delete' '한글 Xbox판 삭제 (Xbox 이름 안 씀)'))
                } elseif ($upSha -ne $pd.xbox_sha) {
                    $plan.Add((Plan-Item 'update/POPData.BF' 'move' '영어판 → 백업 폴더로 옮김 (한글 메뉴를 가리므로)'))
                }
            }
        } elseif ($wantXbox) {
            $plan.Add((Plan-Item 'update/POPData.BF' 'xbox' '새로 만듦: 한글 + Xbox 버튼 이름'))
        }

        # menus
        foreach ($m in @($Man.files.menu)) {
            $p = Game-File $m.path
            if (-not (Test-Path -LiteralPath $p)) { throw "$(Show-Rel $m.path) 이(가) 없습니다." }
            $mb = [IO.File]::ReadAllBytes($p)
            $ms = Sha-Bytes $mb
            if ($ms -eq $m.target_sha) { $plan.Add((Plan-Item $m.path 'done' '한글 (설치되어 있음)')) }
            elseif ($ms -eq $m.stock_sha) { $i = Plan-Item $m.path 'menu' '원본 → 한글'; $i.Bytes = $mb; $i.Spec = $m; $plan.Add($i) }
            else { throw "$(Show-Rel $m.path) 이(가) Steam 원본이 아닙니다. Steam에서 ""게임 파일 무결성 검사""를 한 뒤 다시 실행해 주세요." }
        }

        # The Unofficial Patch 2.1: launcher -> POP2.EXE, POP_WW.asi (unmodified) -> scripts\
        if ($useUnofficial) {
            if ($launcherText -match '"bin"\s*:\s*"POP2\.EXE"') {
                $plan.Add((Plan-Item 'launcher.json' 'done' 'Fix 런처가 POP2.EXE 실행 (설정되어 있음)'))
            } else {
                $i = Plan-Item 'launcher.json' 'launcher' 'Fix 런처: POP2WW.EXE 대신 POP2.EXE 실행 (비공식 패치용)'
                $i.Text = $launcherText
                $plan.Add($i)
            }
            $inRoot = Game-File $uo.name
            $inScripts = Game-File ('scripts/' + $uo.name)
            $rootSha = if (Test-Path -LiteralPath $inRoot) { Sha-File $inRoot } else { '' }
            $scrSha = if (Test-Path -LiteralPath $inScripts) { Sha-File $inScripts } else { '' }
            if ($scrSha -eq $uo.sha -or $rootSha -eq $uo.sha) {
                $plan.Add((Plan-Item ('scripts/' + $uo.name) 'done' "비공식 패치 $($uo.version) (설치되어 있음)"))
            } elseif ($rootSha -ne '' -or $scrSha -ne '') {
                Warn "다른 버전의 $($uo.name)이(가) 있어 그대로 둡니다 (비공식 패치를 직접 넣으셨다면 그 버전이 쓰입니다)."
            } else {
                $plan.Add((Plan-Item ('scripts/' + $uo.name) 'asi' "새로 넣음: 비공식 패치 $($uo.version) (천·바람·머리카락 물리, 불·연기 효과, 마우스 수정)"))
            }
            $d8 = Game-File 'dinput8.dll'
            if ((Test-Path -LiteralPath $d8) -and (Sha-File $d8) -eq $uo.loader_sha) {
                Warn 'dinput8.dll이 비공식 패치에 들어 있던 ASI 로더로 바뀌어 있습니다. Fix 모음의 dinput8.dll(Xidi, 게임패드)을 다시 넣어 주세요.'
            }
        } elseif ($isKorean -and (Has-Prop $Man.files 'unofficial') -and -not $hasAsi) {
            Say '  (비공식 패치는 Fix 모음의 ASI 로더가 있어야 적용됩니다. Fix 모음을 설치한 뒤 INSTALL.bat을 다시 실행하면 함께 설치됩니다.)'
        }

        # 4K Texture Pack
        if ($hasPack) {
            $jp = Get-JkPlan (Game-File 'Evgesha.JK') $kpr
            switch ($jp.State) {
                'done' { $plan.Add((Plan-Item 'Evgesha.JK' 'done' "4K 팩 목록: 한글과 겹치는 항목 없음 ($($jp.Nov)개)")) }
                'patch' { $i = Plan-Item 'Evgesha.JK' 'jk' "4K 팩 목록 $($jp.Nov) → $($jp.Keep) (한글 글꼴 월드 $($jp.Worlds) 항목 끔)"; $i.Jk = $jp; $plan.Add($i) }
                default { Warn ("4K 텍스처 팩은 건드리지 않습니다: " + $jp.Why + ' → 4K 텍스처가 꺼진 채로 실행될 수 있습니다.') }
            }
        }
    }

    Say '설치 계획' 'Cyan'
    foreach ($i in $plan) { Say ('  {0,-26} {1}' -f (Show-Rel $i.Rel), $i.Note) }
    Say ''
    $todo = @($plan | Where-Object { $_.Action -ne 'done' })
    if ($todo.Count -eq 0) {
        Say '이미 이 버전이 모두 설치되어 있습니다. 바꿀 것이 없습니다.' 'Green'
        return $false
    }
    if (-not (Ask-YesNo '위와 같이 설치할까요?' $true)) { throw '설치를 취소했습니다.' }
    if (-not (Test-Path -LiteralPath $script:BackupDir)) { [void](New-Item -ItemType Directory -Path $script:BackupDir -Force) }

    $koPd = $null
    foreach ($i in $todo) {
        $rel = [string]$i.Rel
        $p = Game-File $rel
        switch ([string]$i.Action) {
            'ranges' {
                $bk = Backup-File $script:BackupDir ($rel + '.kpr')
                Save-KprBackup $bk $kpr $i.Data
                Set-Entry $st @{ path = $rel; method = 'ranges'; backup = ($rel + '.kpr'); old_sha = $bfSpec.old_sha; new_sha = $bfSpec.new_sha }
                Write-Ranges $p $kpr
                if ((Sha-Bytes (Read-Ranges $p $kpr)) -ne $bfSpec.new_sha) { throw "$(Show-Rel $rel) 쓰기 확인 실패" }
            }
            'bringback' {
                Ensure-Parent $p
                Move-Item -LiteralPath (Backup-File $script:BackupDir $rel) -Destination $p
                $st.Files.Remove($rel)
                Save-State $st
                $us = Get-RangesState $p $kpr $bfSpec
                if ($us.State -eq 'old') {
                    $bk = Backup-File $script:BackupDir ($rel + '.kpr')
                    Save-KprBackup $bk $kpr $us.Data
                    Set-Entry $st @{ path = $rel; method = 'ranges'; backup = ($rel + '.kpr'); old_sha = $bfSpec.old_sha; new_sha = $bfSpec.new_sha }
                    Write-Ranges $p $kpr
                    if ((Sha-Bytes (Read-Ranges $p $kpr)) -ne $bfSpec.new_sha) { throw "$(Show-Rel $rel) 쓰기 확인 실패" }
                } elseif ($us.State -ne 'new') {
                    Warn "$(Show-Rel $rel) 을(를) 한글로 바꾸지 못했습니다 (알 수 없는 내용)"
                }
            }
            'move' {
                if ($i.Restore) {
                    $re = Get-Entry $st $rel
                    [void](Restore-Entry $st $re)
                    $st.Files.Remove($rel)
                    Save-State $st
                }
                $b = Backup-File $script:BackupDir $rel
                Ensure-Parent $b
                if (Test-Path -LiteralPath $b) { Remove-Item -LiteralPath $b -Force }
                Move-Item -LiteralPath $p -Destination $b
                Set-Entry $st @{ path = $rel; method = 'moved'; backup = $rel }
            }
            'delete' {
                Clear-ReadOnly $p
                Remove-Item -LiteralPath $p -Force
                $st.Files.Remove($rel)
                Save-State $st
            }
            'exe' {
                $out = Build-Exe $i.Info $exeSpec $i.ForceLaa
                Write-Bytes (Backup-File $script:BackupDir $rel) $i.Info.Bytes
                Set-Entry $st @{ path = $rel; method = 'copy'; backup = $rel; orig_sha = $i.Info.Sha; new_sha = (Sha-Bytes $out) }
                Write-Bytes $p $out
                if ((Sha-File $p) -ne (Sha-Bytes $out)) { throw "$rel 쓰기 확인 실패" }
            }
            'laa' {
                # Korean exe already installed by this version (no Fix then): only the LAA bit changes
                $out = [byte[]]$i.Info.Bytes.Clone()
                Set-Laa $out $i.Info.ChOff $true
                if ((Sha-Bytes $out) -ne $exeSpec.target_laa_sha) { throw "$rel LAA 설정 결과가 예상과 다릅니다" }
                $prev = Get-Entry $st $rel
                if ($null -ne $prev -and $prev.method -eq 'copy') {
                    Set-Entry $st @{ path = $rel; method = 'copy'; backup = [string]$prev.backup; orig_sha = [string]$prev.orig_sha; new_sha = $exeSpec.target_laa_sha }
                }
                Write-Bytes $p $out
            }
            'launcher' {
                $new = [regex]::Replace($i.Text, '("bin"\s*:\s*")POP2WW\.EXE(")', '${1}POP2.EXE${2}')
                $old = [IO.File]::ReadAllBytes($p)
                $newBytes = [Text.Encoding]::UTF8.GetBytes($new)
                if ($old.Length -ge 3 -and $old[0] -eq 0xEF -and $old[1] -eq 0xBB -and $old[2] -eq 0xBF) {
                    $newBytes = [byte[]](@(0xEF, 0xBB, 0xBF) + $newBytes)
                }
                Write-Bytes (Backup-File $script:BackupDir $rel) $old
                Set-Entry $st @{ path = $rel; method = 'copy'; backup = $rel; orig_sha = (Sha-Bytes $old); new_sha = (Sha-Bytes $newBytes) }
                Write-Bytes $p $newBytes
            }
            'asi' {
                $asi = [IO.File]::ReadAllBytes((Join-Path $PatcherDir ($uo.patch -replace '/', '\')))
                if ((Sha-Bytes $asi) -ne $uo.sha) { throw "$($uo.name) 파일이 손상되었습니다" }
                Set-Entry $st @{ path = $rel; method = 'created'; new_sha = $uo.sha }
                Write-Bytes $p $asi
            }
            'popdata' {
                $src = $i.Bytes
                if ((Sha-Bytes $src) -eq $pd.fix_xbox_sha) { $src = Apply-Kpd $src $pd.fix_xbox_patch }
                $out = Apply-Kpd $src $pd.patch
                if ((Sha-Bytes $out) -ne $pd.target_sha) { throw 'POPData.BF 패치 결과가 예상과 다릅니다' }
                Write-Bytes (Backup-File $script:BackupDir $rel) $i.Bytes
                Set-Entry $st @{ path = $rel; method = 'copy'; backup = $rel; orig_sha = (Sha-Bytes $i.Bytes); new_sha = $pd.target_sha }
                Write-Bytes $p $out
                $koPd = $out
            }
            'xbox' {
                if ($null -eq $koPd) {
                    $root = [IO.File]::ReadAllBytes((Game-File 'POPData.BF'))
                    $koPd = $root
                }
                $out = if ((Sha-Bytes $koPd) -eq $pd.xbox_sha) { $koPd } else { Apply-Kpd $koPd $pd.xbox_patch }
                if ((Sha-Bytes $out) -ne $pd.xbox_sha) { throw 'Xbox판 POPData 결과가 예상과 다릅니다' }
                if (Test-Path -LiteralPath $p) {
                    $old = [IO.File]::ReadAllBytes($p)
                    $prev = Get-Entry $st $rel
                    if ($null -ne $prev -and $prev.method -eq 'created') {
                        Set-Entry $st @{ path = $rel; method = 'created'; new_sha = $pd.xbox_sha }
                    } else {
                        Write-Bytes (Backup-File $script:BackupDir $rel) $old
                        Set-Entry $st @{ path = $rel; method = 'copy'; backup = $rel; orig_sha = (Sha-Bytes $old); new_sha = $pd.xbox_sha }
                    }
                } else {
                    Set-Entry $st @{ path = $rel; method = 'created'; new_sha = $pd.xbox_sha }
                }
                Write-Bytes $p $out
            }
            'menu' {
                $out = Apply-Kpd $i.Bytes $i.Spec.patch
                if ((Sha-Bytes $out) -ne $i.Spec.target_sha) { throw "$(Show-Rel $rel) 패치 결과가 예상과 다릅니다" }
                Write-Bytes (Backup-File $script:BackupDir $rel) $i.Bytes
                Set-Entry $st @{ path = $rel; method = 'copy'; backup = $rel; orig_sha = $i.Spec.stock_sha; new_sha = $i.Spec.target_sha }
                Write-Bytes $p $out
            }
            'jk' {
                $jp = $i.Jk
                Write-Bytes (Backup-File $script:BackupDir 'Evgesha.JK.head') $jp.Orig
                Set-Entry $st @{ path = $rel; method = 'jkhead'; backup = 'Evgesha.JK.head'; head_bytes = $jp.Orig.Length
                                 orig_sha = (Sha-Bytes $jp.Orig); new_sha = (Sha-Bytes $jp.New) }
                Write-Head $p $jp.New
                if ((Sha-Bytes ((Read-Head $p $jp.New.Length).Bytes)) -ne (Sha-Bytes $jp.New)) { throw 'Evgesha.JK 쓰기 확인 실패' }
            }
        }
        Say ('  완료    ' + (Show-Rel $rel)) 'Green'
    }
    Save-State $st
    return $true
}

# ------------------------------------------------------------------ main

$exitCode = 0
$logName = ($Man.backup_dir -replace '_backup$', '') + '_log.txt'
try {
    $host.UI.RawUI.WindowTitle = "$($Man.title) v$($Man.version)"
} catch { }
try {
    Say "$($Man.title) v$($Man.version) ($($Man.date))" 'Cyan'
    Say $(if ($Mode -eq 'install') { '설치를 시작합니다.' } else { '제거(원래대로 되돌리기)를 시작합니다.' })
    Say ''
    $script:Game = Find-Game
    $script:BackupDir = Join-Path $script:Game $Man.backup_dir
    Say "게임 폴더: $($script:Game)"
    Assert-NotRunning
    if (-not (Test-Writable $script:Game)) {
        $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $admin) {
            Restart-Elevated
            $NoPause = $true
            return
        }
        throw '게임 폴더에 쓸 수 없습니다 (읽기 전용이거나 다른 프로그램이 쓰는 중).'
    }
    if ($Mode -eq 'install') {
        $changed = [bool](Install-Patch | Select-Object -Last 1)
        Say ''
        if ($changed) {
            if ($script:Warnings) { Say "설치를 마쳤습니다. 위의 주의 사항 $($script:Warnings)개를 확인해 주세요." 'Yellow' }
            else { Say '설치를 마쳤습니다. 게임을 즐겨 주세요!' 'Green' }
        }
        Say "되돌리려면 UNINSTALL.bat을 실행하세요. (원래 파일은 게임 폴더의 $($Man.backup_dir) 폴더에 있습니다 - 지우지 마세요)"
    } else {
        $st = Load-State $script:BackupDir
        if ($st.Files.Count -eq 0) {
            Say "설치 기록($($Man.backup_dir))이 없습니다. 되돌릴 것이 없거나, 백업 폴더가 지워졌습니다." 'Yellow'
            Say '원본으로 되돌리려면 Steam에서 "게임 파일 무결성 검사"를 하고, 쓰던 모드를 다시 설치해 주세요.'
        } else {
            if (-not (Ask-YesNo "설치 전 상태로 되돌릴까요?" $true)) { throw '제거를 취소했습니다.' }
            if (Restore-All $st) {
                Remove-Item -LiteralPath $script:BackupDir -Recurse -Force
                Say ''
                Say '원래대로 되돌렸습니다.' 'Green'
            } else {
                Say ''
                Say "일부를 되돌리지 못했습니다. 위의 내용을 확인해 주세요. 백업 폴더($($Man.backup_dir))는 남겨 두었습니다." 'Yellow'
                $exitCode = 2
            }
        }
    }
} catch {
    Say ''
    Say ('오류: ' + $_.Exception.Message) 'Red'
    Say '바뀐 파일이 있다면 UNINSTALL.bat으로 되돌릴 수 있습니다.' 'Yellow'
    $exitCode = 2
} finally {
    try {
        $logDir = if ($script:Game) { $script:Game } else { $PatcherDir }
        $head = "===== $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) $Mode v$($Man.version) ====="
        [IO.File]::AppendAllText((Join-Path $logDir $logName), ($head + "`r`n" + ($script:Lines -join "`r`n") + "`r`n`r`n"), [Text.Encoding]::UTF8)
    } catch { }
}
if (-not $NoPause) {
    Write-Host ''
    [void](Read-Host '엔터를 누르면 창을 닫습니다')
}
exit $exitCode
