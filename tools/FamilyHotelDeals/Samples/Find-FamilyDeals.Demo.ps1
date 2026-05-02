#requires -Version 7.2
<#
.SYNOPSIS
End-to-end demo for the FamilyHotelDeals module.

.DESCRIPTION
Searches Israeli hotels for a family of 2 adults + 3 kids over a few candidate
weekends, prints the top deals to the console, and writes an HTML report next
to this script.

.EXAMPLE
pwsh -File ./Find-FamilyDeals.Demo.ps1
#>
[CmdletBinding()]
param(
    [string]   $Destination = 'Eilat',
    [datetime] $CheckIn     = (Get-Date '2026-07-15'),
    [datetime] $CheckOut    = (Get-Date '2026-07-19'),
    [int]      $Top         = 8,
    [int[]]    $ChildrenAges = @(8, 6, 3),
    [decimal]  $MaxTotalPrice
)

$modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'FamilyHotelDeals.psd1'
Import-Module $modulePath -Force

Write-Host "🇮🇱  Searching family hotel deals — $Destination, $($CheckIn.ToString('yyyy-MM-dd')) → $($CheckOut.ToString('yyyy-MM-dd'))" -ForegroundColor Cyan
Write-Host "Family: 2 adults + $($ChildrenAges.Count) kids (ages: $($ChildrenAges -join ', '))`n"

$findArgs = @{
    Destination  = $Destination
    CheckIn      = $CheckIn
    CheckOut     = $CheckOut
    ChildrenAges = $ChildrenAges
    Top          = $Top
    SortBy       = 'PricePerPerson'
}
if ($PSBoundParameters.ContainsKey('MaxTotalPrice')) { $findArgs.MaxTotalPrice = $MaxTotalPrice }

$top = Find-BestFamilyHotelDeal @findArgs
$top | Format-FamilyHotelDealReport -As Console -FamilySize ($ChildrenAges.Count + 2)

$reportPath = Join-Path $PSScriptRoot ("deals-{0}-{1}.html" -f $Destination.ToLower(), $CheckIn.ToString('yyyyMMdd'))
$top | Format-FamilyHotelDealReport -As Html -OutFile $reportPath -FamilySize ($ChildrenAges.Count + 2)
Write-Host "`nHTML report: $reportPath" -ForegroundColor Green

Write-Host "`nLive search links (Booking.com + Israeli chains):" -ForegroundColor Yellow
$q = New-FamilyHotelQuery -Destination $Destination -CheckIn $CheckIn -CheckOut $CheckOut -ChildrenAges $ChildrenAges
Search-FamilyHotelDeal -Query $q -Provider BookingCom, IsraeliChains |
    Select-Object Provider, HotelName, Url |
    Format-Table -AutoSize
