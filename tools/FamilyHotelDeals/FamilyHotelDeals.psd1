@{
    RootModule        = 'FamilyHotelDeals.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'b1f4a2d6-7c2e-4d2a-9b5e-2f5a3c9d1e22'
    Author            = 'Family Hotel Deals'
    Description       = 'Search Israeli hotel deals for a family of 2 adults + 3 children. Pluggable providers, normalized deal model, HTML/console reports.'
    PowerShellVersion = '7.2'

    FunctionsToExport = @(
        'Search-FamilyHotelDeal'
        'Find-BestFamilyHotelDeal'
        'Format-FamilyHotelDealReport'
        'Register-FamilyHotelDealProvider'
        'Get-FamilyHotelDealProvider'
        'New-FamilyHotelQuery'
    )
    AliasesToExport   = @('fhd', 'fhd-find', 'fhd-report')

    PrivateData = @{
        PSData = @{
            Tags       = @('Israel', 'Hotel', 'Travel', 'Family', 'Deals')
            ProjectUri = 'https://github.com/gabimaximov28/powershell'
        }
    }
}
