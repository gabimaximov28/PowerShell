#requires -Modules Pester

Describe 'FamilyHotelDeals' {
    BeforeAll {
        $modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'FamilyHotelDeals.psd1'
        Import-Module $modulePath -Force
    }

    Context 'New-FamilyHotelQuery' {
        It 'builds a query with family-of-5 defaults' {
            $q = New-FamilyHotelQuery -Destination Eilat -CheckIn '2026-07-15' -CheckOut '2026-07-19'
            $q.Adults             | Should -Be 2
            $q.ChildrenAges.Count | Should -Be 3
            $q.FamilySize()       | Should -Be 5
            $q.Nights()           | Should -Be 4
        }
        It 'rejects checkout before checkin' {
            { New-FamilyHotelQuery -Destination Eilat -CheckIn '2026-07-19' -CheckOut '2026-07-15' } | Should -Throw
        }
    }

    Context 'Mock provider' {
        It 'returns deals for Eilat' {
            $q = New-FamilyHotelQuery -Destination Eilat -CheckIn '2026-07-15' -CheckOut '2026-07-19'
            $deals = Search-FamilyHotelDeal -Query $q -Provider MockIsraeliHotels
            $deals.Count | Should -BeGreaterThan 0
            ($deals | ForEach-Object { $_.City } | Sort-Object -Unique) | Should -Contain 'Eilat'
        }
        It 'returns only deals that fit the family (or 2-room options)' {
            $q = New-FamilyHotelQuery -Destination Eilat -CheckIn '2026-07-15' -CheckOut '2026-07-19'
            $deals = Search-FamilyHotelDeal -Query $q -Provider MockIsraeliHotels
            foreach ($d in $deals) {
                ($d.RoomCapacity -ge $q.FamilySize() -or $d.RoomsRequired -gt 1) | Should -BeTrue
            }
        }
        It 'enforces RequireSingleRoom' {
            $q = New-FamilyHotelQuery -Destination Eilat -CheckIn '2026-07-15' -CheckOut '2026-07-19' -RequireSingleRoom
            $deals = Search-FamilyHotelDeal -Query $q -Provider MockIsraeliHotels
            foreach ($d in $deals) {
                $d.RoomsRequired   | Should -Be 1
                $d.RoomCapacity    | Should -BeGreaterOrEqual 5
            }
        }
        It 'enforces MaxTotalPrice' {
            $q = New-FamilyHotelQuery -Destination Eilat -CheckIn '2026-07-15' -CheckOut '2026-07-19' -MaxTotalPrice 6000
            $deals = Search-FamilyHotelDeal -Query $q -Provider MockIsraeliHotels
            foreach ($d in $deals) { $d.TotalPrice | Should -BeLessOrEqual 6000 }
        }
    }

    Context 'Find-BestFamilyHotelDeal' {
        It 'returns a sorted top-N list' {
            $top = Find-BestFamilyHotelDeal -Destination Eilat -CheckIn '2026-07-15' -CheckOut '2026-07-19' `
                -Provider MockIsraeliHotels -Top 3 -SortBy PricePerNight
            $top.Count | Should -BeLessOrEqual 3
            for ($i = 1; $i -lt $top.Count; $i++) {
                $top[$i].PricePerNight() | Should -BeGreaterOrEqual $top[$i-1].PricePerNight()
            }
        }
    }

    Context 'Booking.com deep link' {
        It 'returns a deep-link deal when no API key is present' {
            $prev = $env:BOOKING_RAPIDAPI_KEY
            $env:BOOKING_RAPIDAPI_KEY = $null
            try {
                $q = New-FamilyHotelQuery -Destination 'Tel Aviv' -CheckIn '2026-08-01' -CheckOut '2026-08-04'
                $deals = Search-FamilyHotelDeal -Query $q -Provider BookingCom
                $deals.Count             | Should -Be 1
                $deals[0].Url            | Should -Match 'booking\.com/searchresults'
                $deals[0].Url            | Should -Match 'group_adults=2'
                $deals[0].Url            | Should -Match 'group_children=3'
            } finally {
                $env:BOOKING_RAPIDAPI_KEY = $prev
            }
        }
    }

    Context 'Reporting' {
        It 'renders an HTML report with the family size in the header' {
            $q = New-FamilyHotelQuery -Destination Eilat -CheckIn '2026-07-15' -CheckOut '2026-07-19'
            $deals = Find-BestFamilyHotelDeal -Destination Eilat -CheckIn $q.CheckIn -CheckOut $q.CheckOut `
                -Provider MockIsraeliHotels -Top 3
            $tmp = New-TemporaryFile
            try {
                $deals | Format-FamilyHotelDealReport -As Html -OutFile $tmp -FamilySize 5
                $html = Get-Content $tmp -Raw
                $html | Should -Match 'Family of 5'
                $html | Should -Match '<table'
            } finally {
                Remove-Item $tmp -ErrorAction SilentlyContinue
            }
        }
    }
}
