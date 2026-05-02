#requires -Version 7.2

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Domain model
# ---------------------------------------------------------------------------

enum BoardBasis {
    RoomOnly       # ללא ארוחות
    BedAndBreakfast # ארוחת בוקר
    HalfBoard      # חצי פנסיון
    FullBoard      # פנסיון מלא
    AllInclusive   # הכל כלול
}

class FamilyHotelQuery {
    [string]    $Destination       # eg 'Eilat', 'Dead Sea', 'Tiberias', or '*'
    [datetime]  $CheckIn
    [datetime]  $CheckOut
    [int]       $Adults     = 2
    [int[]]     $ChildrenAges = @(8, 6, 3)
    [BoardBasis[]] $BoardBasis = @([BoardBasis]::BedAndBreakfast, [BoardBasis]::HalfBoard)
    [Nullable[decimal]] $MaxTotalPrice
    [string]    $Currency = 'ILS'
    [bool]      $RequireSingleRoom = $false   # if true, only deals where the whole family fits in one room

    [int] Nights() { return [int]([math]::Floor(($this.CheckOut - $this.CheckIn).TotalDays)) }
    [int] FamilySize() { return $this.Adults + $this.ChildrenAges.Count }

    [void] Validate() {
        if ($this.CheckIn -ge $this.CheckOut) {
            throw "CheckIn ($($this.CheckIn.ToString('yyyy-MM-dd'))) must be before CheckOut ($($this.CheckOut.ToString('yyyy-MM-dd')))."
        }
        if ($this.Adults -lt 1) { throw 'At least 1 adult is required.' }
    }
}

class FamilyHotelDeal {
    [string]     $Provider
    [string]     $HotelName
    [string]     $Chain
    [string]     $City
    [int]        $StarRating
    [string]     $RoomType
    [int]        $RoomCapacity
    [int]        $RoomsRequired = 1
    [BoardBasis] $BoardBasis
    [datetime]   $CheckIn
    [datetime]   $CheckOut
    [int]        $Nights
    [decimal]    $TotalPrice
    [string]     $Currency = 'ILS'
    [bool]       $FreeCancellation
    [string]     $Url
    [hashtable]  $Raw

    [decimal] PricePerNight() {
        if ($this.Nights -le 0) { return 0 }
        return [math]::Round($this.TotalPrice / $this.Nights, 2)
    }

    [decimal] PricePerPersonPerNight([int]$familySize) {
        if ($this.Nights -le 0 -or $familySize -le 0) { return 0 }
        return [math]::Round($this.TotalPrice / ($this.Nights * $familySize), 2)
    }
}

# ---------------------------------------------------------------------------
# Provider registry
# ---------------------------------------------------------------------------

# Each provider entry: @{ Name = '...'; Search = { param($query) ... returns FamilyHotelDeal[] } }
$script:Providers = [ordered]@{}

function Register-FamilyHotelDealProvider {
    <#
    .SYNOPSIS
    Register a provider that returns FamilyHotelDeal objects for a given query.

    .PARAMETER Name
    Unique provider name.

    .PARAMETER Search
    A scriptblock receiving a FamilyHotelQuery and returning FamilyHotelDeal[].

    .EXAMPLE
    Register-FamilyHotelDealProvider -Name 'MyApi' -Search { param($q) ... }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]      $Name,
        [Parameter(Mandatory)] [scriptblock] $Search
    )
    $script:Providers[$Name] = [pscustomobject]@{
        Name   = $Name
        Search = $Search
    }
}

function Get-FamilyHotelDealProvider {
    [CmdletBinding()] param([string]$Name)
    if ($Name) { return $script:Providers[$Name] }
    return $script:Providers.Values
}

function New-FamilyHotelQuery {
    <#
    .SYNOPSIS
    Build a FamilyHotelQuery with defaults tuned for a couple + 3 kids.
    #>
    [CmdletBinding()]
    [OutputType([FamilyHotelQuery])]
    param(
        [Parameter(Mandatory)] [string] $Destination,
        [Parameter(Mandatory)] [datetime] $CheckIn,
        [Parameter(Mandatory)] [datetime] $CheckOut,
        [int]       $Adults = 2,
        [int[]]     $ChildrenAges = @(8, 6, 3),
        [BoardBasis[]] $BoardBasis = @([BoardBasis]::BedAndBreakfast, [BoardBasis]::HalfBoard),
        [Nullable[decimal]] $MaxTotalPrice,
        [string]    $Currency = 'ILS',
        [switch]    $RequireSingleRoom
    )
    $q = [FamilyHotelQuery]::new()
    $q.Destination       = $Destination
    $q.CheckIn           = $CheckIn.Date
    $q.CheckOut          = $CheckOut.Date
    $q.Adults            = $Adults
    $q.ChildrenAges      = $ChildrenAges
    $q.BoardBasis        = $BoardBasis
    $q.MaxTotalPrice     = $MaxTotalPrice
    $q.Currency          = $Currency
    $q.RequireSingleRoom = [bool]$RequireSingleRoom
    $q.Validate()
    return $q
}

# ---------------------------------------------------------------------------
# Search
# ---------------------------------------------------------------------------

function Search-FamilyHotelDeal {
    <#
    .SYNOPSIS
    Run a query against every registered provider and return normalized deals.

    .PARAMETER Query
    A FamilyHotelQuery (use New-FamilyHotelQuery).

    .PARAMETER Provider
    Limit to specific provider names. Default: all registered providers.

    .EXAMPLE
    $q = New-FamilyHotelQuery -Destination Eilat -CheckIn 2026-07-15 -CheckOut 2026-07-19
    Search-FamilyHotelDeal -Query $q | Sort-Object TotalPrice | Select-Object -First 10
    #>
    [CmdletBinding()]
    [OutputType([FamilyHotelDeal[]])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] [FamilyHotelQuery] $Query,
        [string[]] $Provider
    )
    process {
        $Query.Validate()

        $providers = if ($Provider) {
            $Provider | ForEach-Object {
                $p = $script:Providers[$_]
                if (-not $p) { throw "Unknown provider '$_'. Registered: $($script:Providers.Keys -join ', ')" }
                $p
            }
        } else {
            $script:Providers.Values
        }

        if (-not $providers) {
            Write-Warning 'No providers registered. Import the module again or use Register-FamilyHotelDealProvider.'
            return
        }

        $deals = foreach ($p in $providers) {
            try {
                & $p.Search $Query
            } catch {
                Write-Warning "Provider '$($p.Name)' failed: $($_.Exception.Message)"
            }
        }

        $deals = @($deals) | Where-Object { $_ -is [FamilyHotelDeal] }

        # Server-side filters that don't depend on provider implementation
        if ($Query.MaxTotalPrice) {
            $deals = $deals | Where-Object { $_.TotalPrice -le $Query.MaxTotalPrice }
        }
        if ($Query.RequireSingleRoom) {
            $deals = $deals | Where-Object { $_.RoomsRequired -eq 1 -and $_.RoomCapacity -ge $Query.FamilySize() }
        }

        return $deals
    }
}

function Find-BestFamilyHotelDeal {
    <#
    .SYNOPSIS
    Convenience wrapper. Search and return the top-N cheapest deals per night.

    .EXAMPLE
    Find-BestFamilyHotelDeal -Destination Eilat -CheckIn 2026-07-15 -CheckOut 2026-07-19 -Top 5
    #>
    [CmdletBinding()]
    [OutputType([FamilyHotelDeal[]])]
    param(
        [Parameter(Mandatory)] [string]   $Destination,
        [Parameter(Mandatory)] [datetime] $CheckIn,
        [Parameter(Mandatory)] [datetime] $CheckOut,
        [int[]]    $ChildrenAges = @(8, 6, 3),
        [int]      $Adults  = 2,
        [int]      $Top     = 10,
        [Nullable[decimal]] $MaxTotalPrice,
        [switch]   $RequireSingleRoom,
        [string[]] $Provider,
        [ValidateSet('TotalPrice', 'PricePerNight', 'PricePerPerson', 'StarRating')]
        [string]   $SortBy = 'PricePerNight'
    )
    $q = New-FamilyHotelQuery -Destination $Destination -CheckIn $CheckIn -CheckOut $CheckOut `
        -Adults $Adults -ChildrenAges $ChildrenAges -MaxTotalPrice $MaxTotalPrice `
        -RequireSingleRoom:$RequireSingleRoom

    $deals = Search-FamilyHotelDeal -Query $q -Provider $Provider
    # Filter out deep-link placeholders (TotalPrice = 0) — they aren't real deals
    # to compare. The user can still call Search-FamilyHotelDeal directly to see them.
    $deals = $deals | Where-Object { $_.TotalPrice -gt 0 }
    if (-not $deals) { return @() }

    $familySize = $q.FamilySize()
    $sorted = switch ($SortBy) {
        'TotalPrice'     { $deals | Sort-Object TotalPrice }
        'PricePerNight'  { $deals | Sort-Object { $_.PricePerNight() } }
        'PricePerPerson' { $deals | Sort-Object { $_.PricePerPersonPerNight($familySize) } }
        'StarRating'     { $deals | Sort-Object StarRating -Descending }
    }
    return $sorted | Select-Object -First $Top
}

# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------

function Format-FamilyHotelDealReport {
    <#
    .SYNOPSIS
    Render deals as a console table or an HTML report.

    .EXAMPLE
    $deals | Format-FamilyHotelDealReport -As Html -OutFile ./deals.html
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] [FamilyHotelDeal] $Deal,
        [ValidateSet('Console', 'Html', 'Markdown')] [string] $As = 'Console',
        [string] $OutFile,
        [int]    $FamilySize = 5
    )
    begin { $all = [System.Collections.Generic.List[FamilyHotelDeal]]::new() }
    process { $all.Add($Deal) }
    end {
        if ($all.Count -eq 0) {
            Write-Warning 'No deals to report.'
            return
        }

        $rows = $all | ForEach-Object {
            [pscustomobject]@{
                Hotel        = $_.HotelName
                Chain        = $_.Chain
                City         = $_.City
                Stars        = '★' * [math]::Min($_.StarRating, 5)
                Room         = $_.RoomType
                Sleeps       = $_.RoomCapacity
                Rooms        = $_.RoomsRequired
                Board        = $_.BoardBasis
                Nights       = $_.Nights
                Total        = '{0:N0} {1}' -f $_.TotalPrice, $_.Currency
                PerNight     = '{0:N0}'     -f $_.PricePerNight()
                PerPersonNgt = '{0:N0}'     -f $_.PricePerPersonPerNight($FamilySize)
                Cancel       = if ($_.FreeCancellation) { 'Free' } else { 'Non-ref' }
                Provider     = $_.Provider
                Url          = $_.Url
            }
        }

        switch ($As) {
            'Console' {
                # Force a generous render width so the table is visible when stdout
                # isn't a TTY (CI, docker exec, bash captures). On a real terminal
                # the user can still pipe to Format-Table themselves.
                $width = $Host.UI.RawUI.BufferSize.Width
                if ($width -le 0) { $width = 220 }
                $rows |
                    Format-Table -Property Hotel, City, Stars, Room, Sleeps, Rooms, Board, Nights, Total, PerNight, PerPersonNgt, Cancel, Provider |
                    Out-String -Width $width
            }
            'Markdown' {
                $md = "| Hotel | City | ★ | Room | Sleeps | Board | Nights | Total | /Night | /Person/Night | Cancel |`n"
                $md += "|---|---|---|---|---|---|---|---|---|---|---|`n"
                foreach ($r in $rows) {
                    $md += "| [$($r.Hotel)]($($r.Url)) | $($r.City) | $($r.Stars) | $($r.Room) | $($r.Sleeps) | $($r.Board) | $($r.Nights) | $($r.Total) | $($r.PerNight) | $($r.PerPersonNgt) | $($r.Cancel) |`n"
                }
                if ($OutFile) { $md | Set-Content -Path $OutFile -Encoding utf8 } else { $md }
            }
            'Html' {
                $title = "Family Hotel Deals — $($all[0].CheckIn.ToString('yyyy-MM-dd')) → $($all[0].CheckOut.ToString('yyyy-MM-dd'))"
                $style = @'
<style>
body{font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;margin:24px;color:#222}
h1{font-size:20px;margin-bottom:4px}.sub{color:#666;margin-bottom:16px}
table{border-collapse:collapse;width:100%;font-size:13px}
th,td{border:1px solid #e0e0e0;padding:8px 10px;text-align:left}
th{background:#f6f8fa;position:sticky;top:0}
tr:nth-child(even){background:#fafbfc}
a{color:#0366d6;text-decoration:none}a:hover{text-decoration:underline}
.stars{color:#f5a623}.cheapest{background:#e6ffed}
</style>
'@
                $cheapest = ($rows | Sort-Object { [decimal]($_.PerNight -replace ',', '') } | Select-Object -First 1).Hotel
                $tbody = ($rows | ForEach-Object {
                    $cls = if ($_.Hotel -eq $cheapest) { ' class="cheapest"' } else { '' }
                    "<tr$cls><td><a href='$($_.Url)' target='_blank' rel='noopener'>$($_.Hotel)</a></td><td>$($_.City)</td><td class='stars'>$($_.Stars)</td><td>$($_.Room)</td><td>$($_.Sleeps)</td><td>$($_.Board)</td><td>$($_.Nights)</td><td>$($_.Total)</td><td>$($_.PerNight)</td><td>$($_.PerPersonNgt)</td><td>$($_.Cancel)</td><td>$($_.Provider)</td></tr>"
                }) -join "`n"
                $html = @"
<!doctype html><html lang='he' dir='rtl'><head><meta charset='utf-8'><title>$title</title>$style</head>
<body><h1>$title</h1><div class='sub'>Family of $FamilySize · $($rows.Count) deals · cheapest highlighted</div>
<table><thead><tr><th>Hotel</th><th>City</th><th>★</th><th>Room</th><th>Sleeps</th><th>Board</th><th>Nights</th><th>Total</th><th>/Night</th><th>/Person/Night</th><th>Cancel</th><th>Provider</th></tr></thead>
<tbody>$tbody</tbody></table></body></html>
"@
                if ($OutFile) { $html | Set-Content -Path $OutFile -Encoding utf8 } else { $html }
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Aliases
# ---------------------------------------------------------------------------

Set-Alias -Name fhd        -Value Search-FamilyHotelDeal
Set-Alias -Name fhd-find   -Value Find-BestFamilyHotelDeal
Set-Alias -Name fhd-report -Value Format-FamilyHotelDealReport

# ---------------------------------------------------------------------------
# Auto-load built-in providers
# ---------------------------------------------------------------------------

$providersDir = Join-Path $PSScriptRoot 'Providers'
if (Test-Path $providersDir) {
    Get-ChildItem -Path $providersDir -Filter '*.ps1' | Sort-Object Name | ForEach-Object {
        . $_.FullName
    }
}
