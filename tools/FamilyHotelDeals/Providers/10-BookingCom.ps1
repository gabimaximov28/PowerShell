# Booking.com provider — skeleton.
#
# Booking.com has no public REST endpoint for ad-hoc availability searches; you
# need either:
#   1. The Booking.com Affiliate Partner API (requires partner credentials), or
#   2. A scraper-friendly third-party (e.g. RapidAPI Booking.com endpoints), or
#   3. To open the public search URL in a browser for the user to inspect.
#
# This provider chooses option 3 by default: it builds a deep-link search URL
# for the user. If $env:BOOKING_RAPIDAPI_KEY is set, it falls back to a
# RapidAPI-style HTTP call that returns parsed deals.

function Script:ConvertTo-BookingCity {
    param([string]$Destination)
    switch -Regex ($Destination) {
        '^(?i)eilat|אילת'         { 'Eilat, Israel' }
        '^(?i)dead\s*sea|ים המלח' { 'Dead Sea, Israel' }
        '^(?i)tiberias|טבריה'    { 'Tiberias, Israel' }
        '^(?i)jerusalem|ירושלים' { 'Jerusalem, Israel' }
        '^(?i)tel\s*aviv|תל אביב' { 'Tel Aviv, Israel' }
        '^(?i)netanya|נתניה'     { 'Netanya, Israel' }
        '^(?i)haifa|חיפה'        { 'Haifa, Israel' }
        default                  { "$Destination, Israel" }
    }
}

function Script:Get-BookingSearchUrl {
    param([FamilyHotelQuery]$Query)
    $city = ConvertTo-BookingCity -Destination $Query.Destination
    $params = @{
        ss              = $city
        checkin         = $Query.CheckIn.ToString('yyyy-MM-dd')
        checkout        = $Query.CheckOut.ToString('yyyy-MM-dd')
        group_adults    = $Query.Adults
        group_children  = $Query.ChildrenAges.Count
        no_rooms        = 1
        selected_currency = $Query.Currency
    }
    $qs = ($params.GetEnumerator() | ForEach-Object {
        '{0}={1}' -f $_.Key, [uri]::EscapeDataString([string]$_.Value)
    }) -join '&'
    if ($Query.ChildrenAges.Count -gt 0) {
        $ages = ($Query.ChildrenAges | ForEach-Object { "age=$_" }) -join '&'
        $qs += '&' + $ages
    }
    return "https://www.booking.com/searchresults.html?$qs"
}

Register-FamilyHotelDealProvider -Name 'BookingCom' -Search {
    param([FamilyHotelQuery]$Query)

    $url = Get-BookingSearchUrl -Query $Query
    $key = $env:BOOKING_RAPIDAPI_KEY
    $host_ = $env:BOOKING_RAPIDAPI_HOST  # eg 'booking-com.p.rapidapi.com'

    if (-not $key -or -not $host_) {
        Write-Verbose "[BookingCom] No BOOKING_RAPIDAPI_KEY/HOST set. Returning a single deep-link 'deal' so the user can open the live page."
        $deal = [FamilyHotelDeal]::new()
        $deal.Provider      = 'BookingCom'
        $deal.HotelName     = "(open Booking.com search for $($Query.Destination))"
        $deal.City          = $Query.Destination
        $deal.RoomType      = 'See live results'
        $deal.RoomCapacity  = $Query.FamilySize()
        $deal.BoardBasis    = $Query.BoardBasis[0]
        $deal.CheckIn       = $Query.CheckIn
        $deal.CheckOut      = $Query.CheckOut
        $deal.Nights        = $Query.Nights()
        $deal.TotalPrice    = 0
        $deal.Currency      = $Query.Currency
        $deal.Url           = $url
        $deal.Raw           = @{ DeepLinkOnly = $true }
        return @($deal)
    }

    # RapidAPI shape: this is a reference implementation. Replace with your
    # actual partner / aggregator endpoint.
    $headers = @{
        'X-RapidAPI-Key'  = $key
        'X-RapidAPI-Host' = $host_
    }
    $endpoint = "https://$host_/v1/hotels/search"
    $body = @{
        dest_type        = 'city'
        dest_id          = $Query.Destination
        checkin_date     = $Query.CheckIn.ToString('yyyy-MM-dd')
        checkout_date    = $Query.CheckOut.ToString('yyyy-MM-dd')
        adults_number    = $Query.Adults
        children_number  = $Query.ChildrenAges.Count
        children_ages    = $Query.ChildrenAges -join ','
        room_number      = 1
        order_by         = 'price'
        locale           = 'en-gb'
        currency         = $Query.Currency
        units            = 'metric'
    }
    try {
        $response = Invoke-RestMethod -Uri $endpoint -Headers $headers -Body $body -Method Get -TimeoutSec 30
    } catch {
        Write-Warning "[BookingCom] HTTP call failed: $($_.Exception.Message)"
        return @()
    }

    $results = @()
    foreach ($item in @($response.result)) {
        $deal = [FamilyHotelDeal]::new()
        $deal.Provider         = 'BookingCom'
        $deal.HotelName        = $item.hotel_name
        $deal.City             = $item.city
        $deal.StarRating       = [int]($item.class)
        $deal.RoomType         = $item.unit_configuration_label
        $deal.RoomCapacity     = $Query.FamilySize()
        $deal.BoardBasis       = $Query.BoardBasis[0]
        $deal.CheckIn          = $Query.CheckIn
        $deal.CheckOut         = $Query.CheckOut
        $deal.Nights           = $Query.Nights()
        $deal.TotalPrice       = [decimal]$item.min_total_price
        $deal.Currency         = $item.currencycode
        $deal.FreeCancellation = [bool]$item.is_free_cancellable
        $deal.Url              = $item.url
        $deal.Raw              = @{ Booking = $item }
        $results += $deal
    }
    return $results
}
