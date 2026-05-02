# Mock provider with realistic Israeli family hotels.
# Use it for offline demos, tests, and as a reference for the deal shape
# that real providers must return.

$script:MockHotelCatalog = @(
    # Eilat
    @{ Hotel='Royal Beach';            Chain='Isrotel';   City='Eilat';     Stars=5; Url='https://www.isrotel.com/hotels/royal-beach/' }
    @{ Hotel='Dan Eilat';              Chain='Dan';       City='Eilat';     Stars=5; Url='https://www.danhotels.com/eilat-hotels/dan-eilat/' }
    @{ Hotel='Leonardo Plaza Eilat';   Chain='Fattal';    City='Eilat';     Stars=4; Url='https://www.fattal-hotels.co.il/hotels/leonardo-plaza-eilat/' }
    @{ Hotel='Club Hotel Eilat';       Chain='Club';      City='Eilat';     Stars=4; Url='https://www.clubhotel.co.il/' }
    @{ Hotel='Herods Palace';          Chain='Fattal';    City='Eilat';     Stars=5; Url='https://www.fattal-hotels.co.il/hotels/herods-palace/' }

    # Dead Sea
    @{ Hotel='Isrotel Dead Sea';       Chain='Isrotel';   City='Dead Sea';  Stars=5; Url='https://www.isrotel.com/hotels/dead-sea/' }
    @{ Hotel='David Dead Sea';         Chain='Fattal';    City='Dead Sea';  Stars=5; Url='https://www.fattal-hotels.co.il/hotels/david-dead-sea/' }
    @{ Hotel='Leonardo Club Dead Sea'; Chain='Fattal';    City='Dead Sea';  Stars=4; Url='https://www.fattal-hotels.co.il/hotels/leonardo-club-dead-sea/' }
    @{ Hotel='Herods Dead Sea';        Chain='Fattal';    City='Dead Sea';  Stars=5; Url='https://www.fattal-hotels.co.il/hotels/herods-dead-sea/' }

    # Tiberias
    @{ Hotel='Leonardo Tiberias';      Chain='Fattal';    City='Tiberias';  Stars=4; Url='https://www.fattal-hotels.co.il/hotels/leonardo-tiberias/' }
    @{ Hotel='U Boutique Kinneret';    Chain='Fattal';    City='Tiberias';  Stars=4; Url='https://www.fattal-hotels.co.il/hotels/u-boutique-kinneret/' }
    @{ Hotel='Rimonim Galei Kinnereth'; Chain='Rimonim';  City='Tiberias';  Stars=5; Url='https://www.rimonim.com/' }

    # Netanya / Herzliya
    @{ Hotel='Island Suites';          Chain='Atlas';     City='Netanya';   Stars=4; Url='https://www.atlas.co.il/island-hotel-netanya/' }
    @{ Hotel='Ramada Hotel Netanya';   Chain='Ramada';    City='Netanya';   Stars=4; Url='https://www.ramadanetanya.com/' }
    @{ Hotel='Dan Accadia Herzliya';   Chain='Dan';       City='Herzliya';  Stars=5; Url='https://www.danhotels.com/herzliya-hotels/dan-accadia-herzliya/' }

    # Jerusalem
    @{ Hotel='Leonardo Plaza Jerusalem'; Chain='Fattal';  City='Jerusalem'; Stars=4; Url='https://www.fattal-hotels.co.il/hotels/leonardo-plaza-jerusalem/' }
    @{ Hotel='Inbal Jerusalem';        Chain='Inbal';     City='Jerusalem'; Stars=5; Url='https://www.inbalhotel.com/' }
    @{ Hotel='Prima Park Jerusalem';   Chain='Prima';     City='Jerusalem'; Stars=4; Url='https://www.prima-hotels-israel.com/' }

    # Galilee
    @{ Hotel='Pastoral Kfar Blum';     Chain='Independent'; City='Galilee'; Stars=4; Url='https://www.pastoral.co.il/' }
    @{ Hotel='Ramot Resort';           Chain='Independent'; City='Galilee'; Stars=4; Url='https://www.ramotresort.com/' }
)

# Family-room types and their capacities. The mock decides per hotel which
# variants exist and how price scales with capacity.
$script:MockRoomTypes = @(
    @{ Name='Standard Double';      Capacity=2; Multiplier=1.00 }
    @{ Name='Standard + Sofa';      Capacity=3; Multiplier=1.10 }
    @{ Name='Family Room';          Capacity=4; Multiplier=1.25 }
    @{ Name='Family Suite';         Capacity=5; Multiplier=1.55 }
    @{ Name='Two Connecting Rooms'; Capacity=6; Multiplier=1.85; Rooms=2 }
)

function Script:Get-MockSeasonalFactor {
    param([datetime]$CheckIn, [string]$City)

    $month = $CheckIn.Month
    $base = switch ($City) {
        'Eilat'    { if ($month -in 6..8) { 1.45 } elseif ($month -in 12, 1, 2) { 1.20 } else { 1.0 } }
        'Dead Sea' { if ($month -in 3, 4, 10) { 1.20 } else { 1.0 } }
        default    { if ($month -in 7, 8) { 1.30 } elseif ($month -in 4, 9) { 1.10 } else { 1.0 } }
    }

    # Israeli holiday peaks: rough heuristic — Pesach/Sukkot/Hanukkah windows.
    $peakWindows = @(
        @{ Start = [datetime]'2026-04-01'; End = [datetime]'2026-04-09' }  # Pesach
        @{ Start = [datetime]'2026-09-25'; End = [datetime]'2026-10-04' }  # Sukkot
        @{ Start = [datetime]'2026-12-04'; End = [datetime]'2026-12-12' }  # Hanukkah
    )
    foreach ($w in $peakWindows) {
        if ($CheckIn.Date -ge $w.Start -and $CheckIn.Date -le $w.End) {
            $base *= 1.35
            break
        }
    }

    return [math]::Round($base, 2)
}

function Script:New-MockDeal {
    param(
        [hashtable]$Hotel,
        [hashtable]$RoomType,
        [BoardBasis]$Board,
        [FamilyHotelQuery]$Query
    )

    $nights = $Query.Nights()
    $seasonal = Get-MockSeasonalFactor -CheckIn $Query.CheckIn -City $Hotel.City
    # Base nightly per-adult price varies by stars and chain
    $baseAdult = switch ($Hotel.Stars) { 5 { 720 } 4 { 480 } default { 320 } }
    if ($Hotel.Chain -in 'Dan', 'Isrotel', 'Inbal') { $baseAdult *= 1.10 }

    $boardSurcharge = switch ($Board) {
        ([BoardBasis]::RoomOnly)        { 0 }
        ([BoardBasis]::BedAndBreakfast) { 60 }
        ([BoardBasis]::HalfBoard)       { 180 }
        ([BoardBasis]::FullBoard)       { 280 }
        ([BoardBasis]::AllInclusive)    { 360 }
    }

    # Children priced at ~50% of adult rate
    $effectivePeople = $Query.Adults + ($Query.ChildrenAges.Count * 0.5)
    $nightly = ($baseAdult + $boardSurcharge) * $effectivePeople * $RoomType.Multiplier * $seasonal
    $total = [math]::Round($nightly * $nights, 2)

    $rooms = if ($RoomType.ContainsKey('Rooms')) { [int]$RoomType.Rooms } else { 1 }

    $deal = [FamilyHotelDeal]::new()
    $deal.Provider         = 'MockIsraeliHotels'
    $deal.HotelName        = $Hotel.Hotel
    $deal.Chain            = $Hotel.Chain
    $deal.City             = $Hotel.City
    $deal.StarRating       = $Hotel.Stars
    $deal.RoomType         = $RoomType.Name
    $deal.RoomCapacity     = $RoomType.Capacity
    $deal.RoomsRequired    = $rooms
    $deal.BoardBasis       = $Board
    $deal.CheckIn          = $Query.CheckIn
    $deal.CheckOut         = $Query.CheckOut
    $deal.Nights           = $nights
    $deal.TotalPrice       = $total
    $deal.Currency         = $Query.Currency
    $deal.FreeCancellation = ($total -gt 4000)  # cheaper rates often non-refundable
    $deal.Url              = $Hotel.Url
    $deal.Raw              = @{ SeasonalFactor = $seasonal }
    return $deal
}

Register-FamilyHotelDealProvider -Name 'MockIsraeliHotels' -Search {
    param([FamilyHotelQuery]$Query)

    $familySize = $Query.FamilySize()
    $hotels = if ($Query.Destination -eq '*' -or [string]::IsNullOrWhiteSpace($Query.Destination)) {
        $script:MockHotelCatalog
    } else {
        $script:MockHotelCatalog | Where-Object {
            $_.City -ieq $Query.Destination -or
            $_.City -ilike "*$($Query.Destination)*" -or
            $_.Hotel -ilike "*$($Query.Destination)*"
        }
    }

    $deals = foreach ($h in $hotels) {
        foreach ($room in $script:MockRoomTypes) {
            # Filter rooms that can't house the family at all
            if ($room.Capacity -lt $familySize -and -not $room.ContainsKey('Rooms')) { continue }
            foreach ($board in $Query.BoardBasis) {
                New-MockDeal -Hotel $h -RoomType $room -Board $board -Query $Query
            }
        }
    }

    return $deals
}
