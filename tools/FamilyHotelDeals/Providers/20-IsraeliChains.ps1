# Israeli hotel-chain provider — skeleton.
#
# Fattal/Leonardo, Isrotel, Dan, and Prima all publish public booking-engine
# endpoints used by their websites. They are NOT formally documented for third
# parties; payloads change without notice, and most return Hebrew prices and
# CAPTCHA-protect aggressive scraping.
#
# This provider produces deep-link search URLs by default (no scraping). To
# wire up live availability:
#   * fill in $Endpoints with the actual XHR a chain's site uses, and
#   * map the JSON response to FamilyHotelDeal in Convert-*Response.
#
# Set $env:FHD_LIVE_CHAINS=1 to actually call the live endpoints.

$script:ChainEndpoints = @{
    'Fattal' = @{
        DeepLink = {
            param($q, $cityCode)
            "https://www.fattal-hotels.co.il/?city=$cityCode&checkin=$($q.CheckIn.ToString('yyyy-MM-dd'))&checkout=$($q.CheckOut.ToString('yyyy-MM-dd'))&adults=$($q.Adults)&children=$($q.ChildrenAges.Count)"
        }
        CityCodes = @{
            'Eilat'='1'; 'Dead Sea'='2'; 'Tiberias'='3'; 'Jerusalem'='4'; 'Tel Aviv'='5'; 'Netanya'='6'; 'Haifa'='7'
        }
    }
    'Isrotel' = @{
        DeepLink = {
            param($q, $cityCode)
            "https://www.isrotel.com/booking/?destination=$cityCode&from=$($q.CheckIn.ToString('yyyy-MM-dd'))&to=$($q.CheckOut.ToString('yyyy-MM-dd'))&adults=$($q.Adults)&kids=$($q.ChildrenAges.Count)"
        }
        CityCodes = @{
            'Eilat'='eilat'; 'Dead Sea'='dead-sea'; 'Tel Aviv'='tel-aviv'; 'Tiberias'='tiberias'; 'Jerusalem'='jerusalem'
        }
    }
    'Dan' = @{
        DeepLink = {
            param($q, $cityCode)
            "https://www.danhotels.com/Hotels/?destination=$cityCode&arrivalDate=$($q.CheckIn.ToString('yyyy-MM-dd'))&departureDate=$($q.CheckOut.ToString('yyyy-MM-dd'))&adults=$($q.Adults)&children=$($q.ChildrenAges.Count)"
        }
        CityCodes = @{
            'Eilat'='eilat'; 'Tel Aviv'='tel-aviv'; 'Jerusalem'='jerusalem'; 'Herzliya'='herzliya'; 'Caesarea'='caesarea'
        }
    }
}

function Script:Resolve-CityCode {
    param([hashtable]$Chain, [string]$Destination)
    foreach ($k in $Chain.CityCodes.Keys) {
        if ($k -ieq $Destination -or $Destination -ilike "*$k*") {
            return $Chain.CityCodes[$k]
        }
    }
    return $null
}

Register-FamilyHotelDealProvider -Name 'IsraeliChains' -Search {
    param([FamilyHotelQuery]$Query)

    $live = $env:FHD_LIVE_CHAINS -eq '1'
    $deals = @()

    foreach ($chainName in $script:ChainEndpoints.Keys) {
        $chain = $script:ChainEndpoints[$chainName]
        $code = Resolve-CityCode -Chain $chain -Destination $Query.Destination
        if (-not $code) { continue }

        $url = & $chain.DeepLink $Query $code

        if ($live) {
            Write-Verbose "[IsraeliChains] Live mode is on, but live endpoints for '$chainName' are not implemented. Returning deep link."
            # When you implement: Invoke-RestMethod against the chain's XHR,
            # then convert the response into FamilyHotelDeal objects.
        }

        $deal = [FamilyHotelDeal]::new()
        $deal.Provider         = "IsraeliChains/$chainName"
        $deal.HotelName        = "$chainName — open booking page"
        $deal.Chain            = $chainName
        $deal.City             = $Query.Destination
        $deal.RoomType         = 'See live results'
        $deal.RoomCapacity     = $Query.FamilySize()
        $deal.BoardBasis       = $Query.BoardBasis[0]
        $deal.CheckIn          = $Query.CheckIn
        $deal.CheckOut         = $Query.CheckOut
        $deal.Nights           = $Query.Nights()
        $deal.TotalPrice       = 0
        $deal.Currency         = $Query.Currency
        $deal.Url              = $url
        $deal.Raw              = @{ DeepLinkOnly = $true; Chain = $chainName }
        $deals += $deal
    }

    return $deals
}
