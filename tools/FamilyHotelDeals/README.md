# FamilyHotelDeals

> מודול PowerShell לחיפוש דילים לחופשה משפחתית של זוג + 3 ילדים במלונות בישראל.
> A PowerShell module for finding hotel deals for a family of 2 adults + 3 kids in Israel.

## למה זה קיים / Why

לזוג עם 3 ילדים יש בעיה ייחודית: רוב חדרי המלון בישראל מתאימים לעד 4 אנשים. צריך
לחפש סוויטות משפחתיות, חדרים מחברים, או שני חדרים נפרדים — וכל אתר הזמנות
מציג את זה אחרת. המודול הזה:

- מנרמל דילים ל-`FamilyHotelDeal` אחיד (תמחור, קיבולת, סוג חדר, ביטול).
- מסמן אם המשפחה נכנסת לחדר אחד (`RoomCapacity ≥ 5`) או שצריך שניים.
- מתחבר לכמה ספקים דרך מערכת providers בהרחבה.
- מפיק דוח HTML/Markdown/קונסולה מסודר.

## התקנה / Install

```powershell
Import-Module ./tools/FamilyHotelDeals/FamilyHotelDeals.psd1
```

## שימוש מהיר / Quick start

```powershell
# קונסולה — 5 הדילים הזולים ביותר לאילת בקיץ 2026
Find-BestFamilyHotelDeal -Destination Eilat -CheckIn 2026-07-15 -CheckOut 2026-07-19 -Top 5 |
    Format-FamilyHotelDealReport

# דורש חדר אחד שמתאים ל-5 אנשים, חצי פנסיון, עד 8000 ש"ח
$q = New-FamilyHotelQuery -Destination 'Dead Sea' `
        -CheckIn 2026-04-15 -CheckOut 2026-04-19 `
        -ChildrenAges 10,7,4 -RequireSingleRoom -MaxTotalPrice 8000 `
        -BoardBasis HalfBoard
Search-FamilyHotelDeal -Query $q | Sort-Object { $_.PricePerNight() } |
    Format-FamilyHotelDealReport -As Html -OutFile ./deals.html
```

הרץ את הדוגמה המלאה:
```powershell
pwsh -File ./tools/FamilyHotelDeals/Samples/Find-FamilyDeals.Demo.ps1 -Destination Eilat
```

## ספקים / Providers

| Provider | מה הוא עושה | מה צריך |
|---|---|---|
| `MockIsraeliHotels` | מחזיר דילים סינתטיים אבל ריאליסטיים מעל קטלוג של ~20 מלונות (Fattal, Isrotel, Dan, Prima, Atlas, Rimonim) עם מודל מחיר עונתי + פיק חגים. שימוש: דמו, פיתוח, טסטים. | אין |
| `BookingCom`        | בונה קישור עמוק (deep link) לעמוד החיפוש של Booking.com עם תאריכים, גילי ילדים ומטבע. אם מוגדר `BOOKING_RAPIDAPI_KEY` — קורא ל-RapidAPI ומחזיר דילים אמיתיים מתורגמים ל-`FamilyHotelDeal`. | רשות: `BOOKING_RAPIDAPI_KEY`, `BOOKING_RAPIDAPI_HOST` |
| `IsraeliChains`     | בונה deep links ל-Fattal, Isrotel ו-Dan לפי עיר ותאריכים. הקריאה החיה ל-XHR של אתרי הרשתות לא ממומשת — האתרים הללו לא חושפים API ציבורי. | רשות: `FHD_LIVE_CHAINS=1` (לכשתממשו) |

### להוסיף ספק משלך

```powershell
Register-FamilyHotelDealProvider -Name 'MyAggregator' -Search {
    param([FamilyHotelQuery]$Query)
    # קוראים ל-API שלכם, ממירים ל-FamilyHotelDeal[]
    $r = Invoke-RestMethod "https://api.example.com/search?city=$($Query.Destination)..."
    foreach ($hit in $r.results) {
        $d = [FamilyHotelDeal]::new()
        $d.Provider     = 'MyAggregator'
        $d.HotelName    = $hit.name
        $d.City         = $hit.city
        $d.StarRating   = $hit.stars
        $d.RoomType     = $hit.room
        $d.RoomCapacity = $hit.sleeps
        $d.BoardBasis   = [BoardBasis]$hit.board
        $d.CheckIn      = $Query.CheckIn
        $d.CheckOut     = $Query.CheckOut
        $d.Nights       = $Query.Nights()
        $d.TotalPrice   = $hit.price
        $d.Currency     = $hit.currency
        $d.Url          = $hit.url
        $d
    }
}
```

## מודל הנתונים / Model

```powershell
class FamilyHotelDeal {
    [string]     Provider          # שם הספק
    [string]     HotelName
    [string]     Chain             # רשת (Fattal/Isrotel/Dan/...)
    [string]     City
    [int]        StarRating
    [string]     RoomType          # 'Family Suite', 'Two Connecting Rooms', ...
    [int]        RoomCapacity      # כמה ראשים נכנסים
    [int]        RoomsRequired     # 1 או 2 (חדרים מחוברים)
    [BoardBasis] BoardBasis        # RoomOnly / BedAndBreakfast / HalfBoard / FullBoard / AllInclusive
    [datetime]   CheckIn / CheckOut
    [int]        Nights
    [decimal]    TotalPrice
    [string]     Currency
    [bool]       FreeCancellation
    [string]     Url
    [hashtable]  Raw               # התשובה הגולמית מהספק

    PricePerNight()
    PricePerPersonPerNight([int]$familySize)
}
```

## פקודות / Cmdlets

| Cmdlet | תיאור |
|---|---|
| `New-FamilyHotelQuery`           | בונה אובייקט שאילתה עם ברירות מחדל לזוג + 3 ילדים. |
| `Search-FamilyHotelDeal`         | מריץ שאילתה מול כל הספקים, מחזיר `FamilyHotelDeal[]`. |
| `Find-BestFamilyHotelDeal`       | wrapper נוח שמחזיר Top-N ממוין (לפי מחיר/לילה ברירת-מחדל). |
| `Format-FamilyHotelDealReport`   | מציג טבלה בקונסולה / מייצר HTML / Markdown. |
| `Register-FamilyHotelDealProvider` | רושם ספק חדש. |
| `Get-FamilyHotelDealProvider`    | מציג את הספקים הרשומים. |

קיצורים: `fhd`, `fhd-find`, `fhd-report`.

## מה לא נעשה במכוון / Non-goals

- אין scraper ל-Fattal/Isrotel/Dan — האתרים שלהם לא חושפים API ציבורי, ו-scraper
  שמשתנה כל שבועיים זה לא משהו שכדאי לתחזק כאן. ה-deep links מספיקים כדי
  להעביר את המשתמש לדף חיפוש מוכן עם תאריכים נכונים.
- אין מטמון רשת. אם יהיה צורך — `Cache.ps1` יתווסף עם hash על `FamilyHotelQuery`.
- אין integration לכרטיסי טיסה / השכרת רכב.

## טסטים / Tests

```powershell
Invoke-Pester ./tools/FamilyHotelDeals/Tests/
```
