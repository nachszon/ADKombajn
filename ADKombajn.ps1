#requires -Version 5.1
# Build: 2.13.8-public
# ADKombajn - rewritten from scratch
# Author: Krzysztof Lipa-Izdebski
# Requirements: Windows PowerShell 5.1 / .NET Framework, no RSAT or ActiveDirectory module.

param(
    [ValidateSet("pl", "en")]
    [string]$Language
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.DirectoryServices
Add-Type -AssemblyName System.DirectoryServices.Protocols
Add-Type -AssemblyName System.Data
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

[System.Windows.Forms.Application]::EnableVisualStyles()
try { [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false) } catch { }
try { [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException) } catch { }


# ==================================================
# Colored TabControl tabs
# ==================================================
# The standard WinForms TabControl does not provide a convenient way to color tab labels.
# A small C# OwnerDraw control is used to avoid Paint/DrawItem event issues after PS2EXE compilation.
# The class name has a version suffix because Add-Type cannot replace a class already loaded in the same session.
try {
    Add-Type -ReferencedAssemblies "System.Windows.Forms","System.Drawing" -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

public class KombajnColorTabControlV21 : TabControl
{
    public Color ValidateTabColor = Color.FromArgb(0, 135, 86);
    public Color ChangeTabColor   = Color.FromArgb(214, 126, 28);
    public Color ManagerTabColor  = Color.FromArgb(35, 98, 170);
    public Color AccountPropsTabColor = Color.FromArgb(0, 140, 132);
    public Color AccountGroupsTabColor = Color.FromArgb(0, 92, 185);
    public Color GroupMembersTabColor = Color.FromArgb(185, 42, 94);
    public Color ManagedGroupsTabColor = Color.FromArgb(82, 104, 201);
    public Color LogTabColor = Color.FromArgb(150, 92, 18);
    public Color InactiveTextColor = Color.FromArgb(45, 55, 70);
    public Color SelectedTextColor = Color.White;

    public KombajnColorTabControlV21()
    {
        this.DrawMode = TabDrawMode.OwnerDrawFixed;
        this.SizeMode = TabSizeMode.Normal;
        this.ItemSize = new Size(126, 34);
    }

    private Color GetBaseColor(int index)
    {
        if (index == 0) return ValidateTabColor;
        if (index == 1) return ChangeTabColor;
        if (index == 2) return AccountPropsTabColor;
        if (index == 3) return AccountGroupsTabColor;
        if (index == 4) return GroupMembersTabColor;
        if (index == 5) return ManagedGroupsTabColor;
        if (index == 6) return ManagerTabColor;
        if (index == 7) return LogTabColor;
        return Color.FromArgb(95, 105, 120);
    }

    private Color Mix(Color a, Color b, int percentB)
    {
        int percentA = 100 - percentB;
        return Color.FromArgb(
            (a.R * percentA + b.R * percentB) / 100,
            (a.G * percentA + b.G * percentB) / 100,
            (a.B * percentA + b.B * percentB) / 100
        );
    }

    private GraphicsPath RoundedRect(Rectangle bounds, int radius)
    {
        int d = radius * 2;
        GraphicsPath path = new GraphicsPath();
        path.AddArc(bounds.X, bounds.Y, d, d, 180, 90);
        path.AddArc(bounds.Right - d, bounds.Y, d, d, 270, 90);
        path.AddArc(bounds.Right - d, bounds.Bottom - d, d, d, 0, 90);
        path.AddArc(bounds.X, bounds.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }

    protected override void OnDrawItem(DrawItemEventArgs e)
    {
        try
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;

            Rectangle r = this.GetTabRect(e.Index);
            r.X += 3;
            r.Y += 4;
            r.Width -= 6;
            r.Height -= 6;

            bool selected = (e.Index == this.SelectedIndex);
            Color baseColor = GetBaseColor(e.Index);
            Color fill1 = selected ? baseColor : Mix(baseColor, Color.White, 72);
            Color fill2 = selected ? Mix(baseColor, Color.Black, 18) : Mix(baseColor, Color.White, 58);
            Color border = selected ? Mix(baseColor, Color.Black, 28) : Mix(baseColor, Color.White, 35);
            Color textColor = selected ? SelectedTextColor : InactiveTextColor;

            using (GraphicsPath path = RoundedRect(r, 8))
            using (LinearGradientBrush brush = new LinearGradientBrush(r, fill1, fill2, LinearGradientMode.Vertical))
            using (Pen pen = new Pen(border))
            {
                g.FillPath(brush, path);
                g.DrawPath(pen, path);
            }

            string text = this.TabPages[e.Index].Text;
            FontStyle style = selected ? FontStyle.Bold : FontStyle.Regular;
            using (Font f = new Font(this.Font.FontFamily, this.Font.Size, style))
            using (Brush textBrush = new SolidBrush(textColor))
            using (StringFormat sf = new StringFormat())
            {
                sf.Alignment = StringAlignment.Center;
                sf.LineAlignment = StringAlignment.Center;
                sf.Trimming = StringTrimming.EllipsisCharacter;
                g.DrawString(text, f, textBrush, r, sf);
            }
        }
        catch
        {
            base.OnDrawItem(e);
        }
    }
}
'@
}
catch { }

# ==================================================
# Application state
# ==================================================

$script:AppName = "ADKombajn"
$script:AppVersion = "2.13.8"
$script:AppAuthor = "Krzysztof Lipa-Izdebski"
$script:UiLanguage = if ($Language -in @("pl", "en")) { $Language.ToLowerInvariant() } else { "" }
$script:ManagedRowsAll = @()
$script:ManagedRowsLoaded = $false
$script:AccountPropertyRows = @()
$script:AccountGroupRows = @()
$script:DomainGroupMemberRows = @()
$script:ManagedGroupRows = @()
$script:MainForm = $null
$script:StatusLabel = $null
$script:txtLog = $null
$script:txtLogs = @()
$script:AppWindowIcon = $null
$script:BrandImageStream = $null
$script:BrandImage = $null

# The green combine is embedded as Base64 so the PowerShell script remains
# a single, self-contained file, just like DataKombajn.
$script:BrandImageBase64 = @'
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

'@

try {
    $brandImageBytes = [Convert]::FromBase64String(($script:BrandImageBase64 -replace '\s', ''))
    $script:BrandImageStream = New-Object System.IO.MemoryStream(,$brandImageBytes)
    $script:BrandImage = [System.Drawing.Image]::FromStream($script:BrandImageStream)
}
catch {
    # Branding must never prevent the application from starting.
    $script:BrandImage = $null
    if ($null -ne $script:BrandImageStream) {
        $script:BrandImageStream.Dispose()
        $script:BrandImageStream = $null
    }
}

# ==================================================
# Localization
# ==================================================

$script:Translations = @{
    pl = @{
        "App.WindowTitle" = "{0} {1} - bez RSAT"
        "Splash.Subtitle" = "HASŁA  •  KONTA  •  GRUPY"
        "Splash.Author" = "Autor: {0}"
        "Splash.Version" = "WERSJA {0}"
        "Splash.Loading" = "Ładuję interfejs..."
        "Header.Subtitle" = "Walidacja, zmiana hasła, właściwości konta, grupy konta, zarządzane konta, log"
        "Header.Author" = "Autor: {0}"
        "Busy.Title" = "Przetwarzanie"
        "Busy.Message" = "Proszę czekać..."
        "Busy.Detail" = "Operacja jest wykonywana w Active Directory."
        "Busy.DoNotClose" = "Proszę nie zamykać aplikacji w trakcie operacji."
        "Error.GuiUnhandled" = "Nieobsłużony błąd interfejsu: {0}"
        "Error.AppTitle" = "Błąd ADKombajna"
        "Ldap.HintPasswordPolicy" = "Prawdopodobnie polityka haseł: złożoność, historia haseł, minimalny wiek hasła albo zbyt krótkie hasło."
        "Ldap.HintCredentials" = "Prawdopodobnie błędny login albo stare hasło."
        "Ldap.HintConnection" = "Nie mogę połączyć się z kontrolerem domeny. Sprawdź domenę/DC, sieć, port 389/636 i LDAPS."
        "Ldap.HintSecureChannel" = "AD wymaga bezpiecznego kanału. Spróbuj LDAPS 636 albo upewnij się, że działa signing/sealing po 389."
        "Ldap.Code" = "Kod: {0}"
        "Ldap.Hint" = "Podpowiedź: {0}"
        "Password.Valid" = "Hasło jest poprawne."
        "Password.Invalid" = "Hasło jest niepoprawne albo konto nie może się uwierzytelnić."
        "Password.Changed" = "Hasło zostało zmienione."
        "Error.AccountNotFound" = "Nie znaleziono konta: {0}\{1}"
        "Error.ManagerNotFound" = "Nie znaleziono wskazanego konta: {0}\{1}"
        "Error.GroupNotFound" = "Nie znaleziono grupy: {0}\{1}"
        "Error.ExportNoAccounts" = "Brak kont do eksportu."
        "Error.ExcelColumn" = "Nieprawidłowy numer kolumny Excela: {0}"
        "Value.Never" = "Nigdy"
        "Value.UnknownObject" = "Nie udało się pobrać obiektu po DN"
        "Progress.FindAccount" = "Szukam konta w AD"
        "Progress.ReadAccount" = "Odczytuję atrybuty konta"
        "Progress.ReadMemberOf" = "Pobieram grupy memberOf"
        "Progress.CheckPrimaryGroup" = "Sprawdzam grupę podstawową"
        "Progress.OrganizeResult" = "Porządkuję wynik"
        "Progress.DeduplicateGroups" = "Usuwam duplikaty i sortuję listę grup..."
        "Progress.ReadMemberList" = "Czytam listę member"
        "Progress.Range" = "Zakres {0} - {1}"
        "Progress.FindGroup" = "Szukam grupy w AD"
        "Progress.GetMemberList" = "Pobieram listę członków"
        "Progress.GetMemberObjects" = "Pobieram obiekty członków"
        "Progress.SortGroupMembers" = "Sortuję listę członków grupy..."
        "Progress.FindManager" = "Szukam wskazanego konta"
        "Progress.FindManagedGroups" = "Szukam zarządzanych grup"
        "Progress.OrganizeManagedGroups" = "Porządkuję zarządzane grupy"
        "Context.Title" = "Kontekst pracy"
        "Context.Domain" = "Domena / DC:"
        "Context.AccountLogin" = "Login konta:"
        "Context.Mode" = "Domyślnie: LDAP 389 + signing/sealing, bez RSAT."
        "Tab.ValidatePassword" = "Walidacja hasła"
        "Tab.ChangePassword" = "Zmiana hasła"
        "Tab.ManagerAccounts" = "Zarządzane konta"
        "Tab.AccountProperties" = "Właściwości konta"
        "Tab.AccountGroups" = "Grupy konta"
        "Tab.GroupMembers" = "Członkowie grupy"
        "Tab.ManagedGroups" = "Zarządzane grupy"
        "Tab.Log" = "Log"
        "Validation.Title" = "Walidacja hasła"
        "Validation.Password" = "Hasło:"
        "Validation.ShowPassword" = "Pokaż hasło"
        "Validation.Check" = "Sprawdź"
        "Validation.Hint" = "Walidacja używa PrincipalContext.ValidateCredentials(), bez RSAT i bez modułu ActiveDirectory."
        "Change.Title" = "Zmiana hasła: stare → nowe"
        "Change.OldPassword" = "Stare hasło:"
        "Change.NewPassword" = "Nowe hasło:"
        "Change.RepeatPassword" = "Powtórz:"
        "Change.ShowPasswords" = "Pokaż hasła"
        "Change.Button" = "Zmień hasło"
        "Change.Hint" = "Zmiana bez UserPrincipal.ChangePassword(): LDAP unicodePwd DELETE starego + ADD nowego."
        "Common.Exit" = "Zamknij"
        "Common.Clear" = "Wyczyść"
        "Common.CopySelected" = "Kopiuj zaznaczone"
        "Common.CopyAll" = "Kopiuj wszystko"
        "Common.Log" = "Log"
        "Common.ClearLog" = "Wyczyść log"
        "Common.CopyLog" = "Kopiuj log"
        "Log.Events" = "Log zdarzeń"
        "AccountProperties.Get" = "Pobierz właściwości"
        "AccountProperties.Info" = "Pokazuje atrybuty LDAP konta, bez RSAT. Odpowiednik podglądu zbliżony do Get-ADUser -Properties *."
        "AccountProperties.CountEmpty" = "Właściwości: -"
        "AccountProperties.Count" = "Właściwości: {0}"
        "AccountGroups.Get" = "Pobierz grupy"
        "AccountGroups.Info" = "Pokazuje grupy domenowe konta: memberOf oraz primaryGroupID, bez RSAT."
        "Groups.CountEmpty" = "Grupy: -"
        "Groups.Count" = "Grupy: {0}"
        "GroupMembers.Group" = "Grupa:"
        "GroupMembers.Get" = "Pobierz członków"
        "GroupMembers.Info" = "Pokazuje bezpośrednich członków grupy domenowej z atrybutu member. Grupy zagnieżdżone są pokazane jako obiekty grupowe, bez rozwijania rekurencyjnego."
        "GroupMembers.CountEmpty" = "Członkowie: -"
        "GroupMembers.Count" = "Członkowie: {0}"
        "ManagedGroups.Get" = "Pobierz grupy"
        "ManagedGroups.Info" = "Pokazuje grupy domenowe zarządzane przez konto z pola Login konta, na podstawie atrybutu managedBy."
        "ManagerAccounts.Get" = "Pobierz konta"
        "ManagerAccounts.ExportCsv" = "Eksport CSV"
        "ManagerAccounts.ExportXlsx" = "Eksport XLSX"
        "ManagerAccounts.CopyLogins" = "Kopiuj loginy"
        "ManagerAccounts.Show" = "Pokaż:"
        "ManagerAccounts.Search" = "Szukaj:"
        "ManagerAccounts.ExportInfo" = "Eksport obejmuje aktualnie widoczne wiersze, czyli filtr + wyszukiwarkę."
        "ManagerAccounts.CountEmpty" = "Konta: -"
        "ManagerAccounts.Count" = "Konta: {0}"
        "ManagerAccounts.CountFiltered" = "Konta: {0} z {1}"
        "Filter.All" = "wszystkie"
        "Filter.Active" = "aktywne"
        "Filter.Inactive" = "nieaktywne"
        "Column.Attribute" = "Atrybut"
        "Column.Value" = "Wartość"
        "Column.Count" = "Ile"
        "Column.Name" = "Nazwa"
        "Column.GroupLogin" = "Login grupy"
        "Column.DisplayName" = "Display name"
        "Column.Type" = "Typ"
        "Column.Scope" = "Zakres"
        "Column.Source" = "Źródło"
        "Column.Description" = "Opis"
        "Column.Login" = "Login"
        "Column.Enabled" = "Aktywne"
        "Column.PasswordLastSet" = "Hasło zmienione"
        "Export.SheetName" = "Zarządzane konta"
        "Export.FileNameBase" = "zarzadzane_konta"
        "Export.NoDataPart" = "brak"
        "Export.SaveTitle" = "Zapisz zarządzane konta"
        "Export.CsvFilter" = "CSV rozdzielany średnikiem (*.csv)|*.csv|Wszystkie pliki (*.*)|*.*"
        "Export.XlsxFilter" = "Excel Workbook (*.xlsx)|*.xlsx|Wszystkie pliki (*.*)|*.*"
        "Dialog.NoData" = "Brak danych"
        "Dialog.NoSelection" = "Brak zaznaczenia"
        "Status.Filter" = "Filtr: {0}, tekst: '{1}' - pokazano {2} z {3} kont."
        "Status.GetManagerAccountsFirst" = "Najpierw pobierz zarządzane konta."
        "Status.FilterHasNoAccounts" = "Bieżący filtr nie zawiera żadnych kont do eksportu."
        "Status.ExportCancelled" = "Eksport anulowany."
        "Status.Exporting" = "Eksportuję {0} kont do {1}..."
        "Status.ExportReady" = "OK - eksport gotowy: {0}"
        "Status.ExportCompleted" = "Eksport zakończony.`r`n`r`nPlik:`r`n{0}"
        "Status.ExportCompletedTitle" = "Eksport gotowy"
        "Status.ExportError" = "Błąd eksportu: {0}"
        "Status.ExportFailed" = "Nie udało się wykonać eksportu.`r`n`r`n{0}"
        "Status.ExportErrorTitle" = "Błąd eksportu"
        "Status.SelectRow" = "Zaznacz co najmniej jeden wiersz."
        "Status.LoginsCopied" = "Skopiowano loginów do schowka: {0}"
        "Status.ClipboardFailed" = "Nie udało się skopiować do schowka: {0}"
        "Status.ReadyShort" = "Gotowy."
        "Status.Ready" = "Gotowy. Podaj domenę/DC i login."
        "Status.LogCleared" = "Log wyczyszczony."
        "Status.LogEmpty" = "Log jest pusty."
        "Status.LogCopied" = "Log skopiowany do schowka."
        "Status.LogCopyFailed" = "Nie udało się skopiować logu: {0}"
        "Status.ValidationPasswordCleared" = "Wyczyszczono hasło walidacji."
        "Status.ChangeFieldsCleared" = "Wyczyszczono pola zmiany hasła."
        "Status.EnterValidationData" = "Podaj domenę/DC, login i hasło do walidacji."
        "Status.ValidatingPassword" = "Sprawdzam hasło dla {0}\{1}..."
        "Status.PasswordValid" = "OK - hasło jest poprawne dla {0}\{1}."
        "Status.PasswordInvalid" = "NIE OK - hasło nie przeszło walidacji."
        "Status.EnterDomainLogin" = "Podaj domenę/DC i login."
        "Status.EnterPasswordChangeData" = "Podaj stare hasło, nowe hasło i powtórzenie nowego hasła."
        "Status.PasswordsDiffer" = "Nowe hasła nie są identyczne."
        "Status.PasswordUnchanged" = "Nowe hasło jest takie samo jak stare."
        "Status.ConfirmPasswordChange" = "Zmienić hasło dla konta {0}\{1}?`r`n`r`nOperacja używa starego i nowego hasła, bez resetu administracyjnego."
        "Status.ConfirmPasswordChangeTitle" = "Potwierdzenie zmiany hasła"
        "Status.PasswordChangeCancelled" = "Zmiana hasła anulowana."
        "Status.ChangingPassword" = "Zmieniam hasło dla {0}\{1}..."
        "Status.PasswordChanged" = "OK - hasło zostało zmienione dla {0}\{1}."
        "Status.PasswordChangeError" = "Błąd zmiany hasła dla {0}\{1}."
        "Status.EnterAccount" = "Podaj domenę/DC i login konta."
        "Status.GettingAccountProperties" = "Pobieram właściwości konta {0}\{1}..."
        "Status.AccountPropertiesReceived" = "OK - pobrano właściwości: {0}."
        "Status.AccountPropertiesError" = "Błąd pobierania właściwości konta: {0}"
        "Status.AccountPropertiesCleared" = "Właściwości konta wyczyszczone."
        "Status.SelectProperties" = "Zaznacz właściwości do skopiowania."
        "Status.PropertiesCopied" = "Skopiowano zaznaczone właściwości: {0}."
        "Status.PropertiesCopyFailed" = "Nie udało się skopiować właściwości: {0}"
        "Status.NoProperties" = "Brak właściwości konta do skopiowania."
        "Status.AllPropertiesCopied" = "Skopiowano wszystkie właściwości: {0}."
        "Status.GettingAccountGroups" = "Pobieram grupy konta {0}\{1}..."
        "Status.NoAccountGroups" = "OK - nie znaleziono grup dla konta {0}\{1}."
        "Status.AccountGroupsReceived" = "OK - pobrano grupy konta: {0}."
        "Status.AccountGroupsError" = "Błąd pobierania grup konta: {0}"
        "Status.AccountGroupsCleared" = "Lista grup konta wyczyszczona."
        "Status.SelectGroups" = "Zaznacz grupy do skopiowania."
        "Status.GroupsCopied" = "Skopiowano zaznaczone grupy: {0}."
        "Status.GroupsCopyFailed" = "Nie udało się skopiować grup: {0}"
        "Status.NoAccountGroupsToCopy" = "Brak grup konta do skopiowania."
        "Status.AllGroupsCopied" = "Skopiowano wszystkie grupy: {0}."
        "Status.EnterDomain" = "Podaj domenę/DC."
        "Status.EnterGroup" = "Podaj nazwę grupy domenowej."
        "Status.GettingGroupMembers" = "Pobieram członków grupy {0}\{1}..."
        "Status.NoGroupMembers" = "OK - grupa {0}\{1} nie ma bezpośrednich członków albo nie udało się ich odczytać."
        "Status.GroupMembersReceived" = "OK - pobrano członków grupy: {0}."
        "Status.GroupMembersError" = "Błąd pobierania członków grupy: {0}"
        "Status.GroupMembersCleared" = "Lista członków grupy wyczyszczona."
        "Status.SelectGroupMembers" = "Zaznacz członków grupy do skopiowania."
        "Status.GroupMembersCopied" = "Skopiowano zaznaczonych członków grupy: {0}."
        "Status.GroupMembersCopyFailed" = "Nie udało się skopiować członków grupy: {0}"
        "Status.NoGroupMembersToCopy" = "Brak członków grupy do skopiowania."
        "Status.AllGroupMembersCopied" = "Skopiowano wszystkich członków grupy: {0}."
        "Status.EnterManager" = "Podaj domenę/DC i login konta zarządzającego."
        "Status.GettingManagedGroups" = "Pobieram grupy zarządzane przez {0}\{1}..."
        "Status.NoManagedGroups" = "OK - nie znaleziono grup zarządzanych przez {0}\{1}."
        "Status.ManagedGroupsReceived" = "OK - znaleziono zarządzane grupy: {0}."
        "Status.ManagedGroupsError" = "Błąd pobierania zarządzanych grup: {0}"
        "Status.ManagedGroupsCleared" = "Lista zarządzanych grup wyczyszczona."
        "Status.SelectManagedGroups" = "Zaznacz zarządzane grupy do skopiowania."
        "Status.ManagedGroupsCopied" = "Skopiowano zaznaczone zarządzane grupy: {0}."
        "Status.ManagedGroupsCopyFailed" = "Nie udało się skopiować zarządzanych grup: {0}"
        "Status.NoManagedGroupsToCopy" = "Brak zarządzanych grup do skopiowania."
        "Status.AllManagedGroupsCopied" = "Skopiowano wszystkie zarządzane grupy: {0}."
        "Status.FindingManagerAccounts" = "Szukam kont zarządzanych przez {0}\{1}..."
        "Status.NoManagerAccounts" = "OK - nie znaleziono kont zarządzanych przez {0}\{1}."
        "Status.ManagerAccountsReceived" = "OK - znaleziono zarządzane konta: {0}; pokazano: {1} ({2})."
        "Status.ManagerAccountsError" = "Błąd pobierania zarządzanych kont: {0}"
        "Status.ManagerAccountsCleared" = "Lista zarządzanych kont wyczyszczona."
    }
    en = @{
        "App.WindowTitle" = "{0} {1} - no RSAT"
        "Splash.Subtitle" = "PASSWORDS  •  ACCOUNTS  •  GROUPS"
        "Splash.Author" = "Author: {0}"
        "Splash.Version" = "VERSION {0}"
        "Splash.Loading" = "Loading interface..."
        "Header.Subtitle" = "Password validation and change, account properties, groups, managed accounts, log"
        "Header.Author" = "Author: {0}"
        "Busy.Title" = "Processing"
        "Busy.Message" = "Please wait..."
        "Busy.Detail" = "The operation is being performed in Active Directory."
        "Busy.DoNotClose" = "Please do not close the application during the operation."
        "Error.GuiUnhandled" = "Unhandled interface error: {0}"
        "Error.AppTitle" = "ADKombajn error"
        "Ldap.HintPasswordPolicy" = "The password policy may have rejected the password because of complexity, history, minimum age, or length requirements."
        "Ldap.HintCredentials" = "The login or old password is probably incorrect."
        "Ldap.HintConnection" = "Cannot connect to the domain controller. Check the domain/DC, network, port 389/636, and LDAPS."
        "Ldap.HintSecureChannel" = "AD requires a secure channel. Try LDAPS 636 or make sure signing/sealing works over port 389."
        "Ldap.Code" = "Code: {0}"
        "Ldap.Hint" = "Hint: {0}"
        "Password.Valid" = "The password is valid."
        "Password.Invalid" = "The password is invalid or the account cannot authenticate."
        "Password.Changed" = "The password has been changed."
        "Error.AccountNotFound" = "Account not found: {0}\{1}"
        "Error.ManagerNotFound" = "Specified account not found: {0}\{1}"
        "Error.GroupNotFound" = "Group not found: {0}\{1}"
        "Error.ExportNoAccounts" = "There are no accounts to export."
        "Error.ExcelColumn" = "Invalid Excel column number: {0}"
        "Value.Never" = "Never"
        "Value.UnknownObject" = "Could not retrieve the object by DN"
        "Progress.FindAccount" = "Searching for the account in AD"
        "Progress.ReadAccount" = "Reading account attributes"
        "Progress.ReadMemberOf" = "Retrieving memberOf groups"
        "Progress.CheckPrimaryGroup" = "Checking the primary group"
        "Progress.OrganizeResult" = "Organizing results"
        "Progress.DeduplicateGroups" = "Removing duplicates and sorting the group list..."
        "Progress.ReadMemberList" = "Reading the member list"
        "Progress.Range" = "Range {0} - {1}"
        "Progress.FindGroup" = "Searching for the group in AD"
        "Progress.GetMemberList" = "Retrieving the member list"
        "Progress.GetMemberObjects" = "Retrieving member objects"
        "Progress.SortGroupMembers" = "Sorting the group member list..."
        "Progress.FindManager" = "Searching for the specified account"
        "Progress.FindManagedGroups" = "Searching for managed groups"
        "Progress.OrganizeManagedGroups" = "Organizing managed groups"
        "Context.Title" = "Working context"
        "Context.Domain" = "Domain / DC:"
        "Context.AccountLogin" = "Account login:"
        "Context.Mode" = "Default: LDAP 389 + signing/sealing, no RSAT."
        "Tab.ValidatePassword" = "Validate password"
        "Tab.ChangePassword" = "Change password"
        "Tab.ManagerAccounts" = "Managed accounts"
        "Tab.AccountProperties" = "Account properties"
        "Tab.AccountGroups" = "Account groups"
        "Tab.GroupMembers" = "Group members"
        "Tab.ManagedGroups" = "Managed groups"
        "Tab.Log" = "Log"
        "Validation.Title" = "Password validation"
        "Validation.Password" = "Password:"
        "Validation.ShowPassword" = "Show password"
        "Validation.Check" = "Validate"
        "Validation.Hint" = "Validation uses PrincipalContext.ValidateCredentials(), without RSAT or the ActiveDirectory module."
        "Change.Title" = "Change password: old → new"
        "Change.OldPassword" = "Old password:"
        "Change.NewPassword" = "New password:"
        "Change.RepeatPassword" = "Repeat:"
        "Change.ShowPasswords" = "Show passwords"
        "Change.Button" = "Change password"
        "Change.Hint" = "Password change without UserPrincipal.ChangePassword(): LDAP unicodePwd DELETE old + ADD new."
        "Common.Exit" = "Exit"
        "Common.Clear" = "Clear"
        "Common.CopySelected" = "Copy selected"
        "Common.CopyAll" = "Copy all"
        "Common.Log" = "Log"
        "Common.ClearLog" = "Clear log"
        "Common.CopyLog" = "Copy log"
        "Log.Events" = "Event log"
        "AccountProperties.Get" = "Get properties"
        "AccountProperties.Info" = "Displays LDAP account attributes without RSAT, similar to Get-ADUser -Properties *."
        "AccountProperties.CountEmpty" = "Properties: -"
        "AccountProperties.Count" = "Properties: {0}"
        "AccountGroups.Get" = "Get groups"
        "AccountGroups.Info" = "Displays account domain groups from memberOf and primaryGroupID without RSAT."
        "Groups.CountEmpty" = "Groups: -"
        "Groups.Count" = "Groups: {0}"
        "GroupMembers.Group" = "Group:"
        "GroupMembers.Get" = "Get members"
        "GroupMembers.Info" = "Displays direct members from the domain group's member attribute. Nested groups are shown as group objects and are not expanded recursively."
        "GroupMembers.CountEmpty" = "Members: -"
        "GroupMembers.Count" = "Members: {0}"
        "ManagedGroups.Get" = "Get groups"
        "ManagedGroups.Info" = "Displays domain groups managed by the account entered in Account login, based on the managedBy attribute."
        "ManagerAccounts.Get" = "Get accounts"
        "ManagerAccounts.ExportCsv" = "Export CSV"
        "ManagerAccounts.ExportXlsx" = "Export XLSX"
        "ManagerAccounts.CopyLogins" = "Copy logins"
        "ManagerAccounts.Show" = "Show:"
        "ManagerAccounts.Search" = "Search:"
        "ManagerAccounts.ExportInfo" = "The export includes the currently visible rows: filter + search."
        "ManagerAccounts.CountEmpty" = "Accounts: -"
        "ManagerAccounts.Count" = "Accounts: {0}"
        "ManagerAccounts.CountFiltered" = "Accounts: {0} of {1}"
        "Filter.All" = "all"
        "Filter.Active" = "active"
        "Filter.Inactive" = "inactive"
        "Column.Attribute" = "Attribute"
        "Column.Value" = "Value"
        "Column.Count" = "Count"
        "Column.Name" = "Name"
        "Column.GroupLogin" = "Group login"
        "Column.DisplayName" = "Display name"
        "Column.Type" = "Type"
        "Column.Scope" = "Scope"
        "Column.Source" = "Source"
        "Column.Description" = "Description"
        "Column.Login" = "Login"
        "Column.Enabled" = "Enabled"
        "Column.PasswordLastSet" = "Password last set"
        "Export.SheetName" = "Managed accounts"
        "Export.FileNameBase" = "managed_accounts"
        "Export.NoDataPart" = "none"
        "Export.SaveTitle" = "Save managed accounts"
        "Export.CsvFilter" = "Semicolon-delimited CSV (*.csv)|*.csv|All files (*.*)|*.*"
        "Export.XlsxFilter" = "Excel Workbook (*.xlsx)|*.xlsx|All files (*.*)|*.*"
        "Dialog.NoData" = "No data"
        "Dialog.NoSelection" = "No selection"
        "Status.Filter" = "Filter: {0}, text: '{1}' - showing {2} of {3} accounts."
        "Status.GetManagerAccountsFirst" = "Retrieve the managed accounts first."
        "Status.FilterHasNoAccounts" = "The current filter contains no accounts to export."
        "Status.ExportCancelled" = "Export cancelled."
        "Status.Exporting" = "Exporting {0} accounts to {1}..."
        "Status.ExportReady" = "OK - export ready: {0}"
        "Status.ExportCompleted" = "Export completed.`r`n`r`nFile:`r`n{0}"
        "Status.ExportCompletedTitle" = "Export ready"
        "Status.ExportError" = "Export error: {0}"
        "Status.ExportFailed" = "The export failed.`r`n`r`n{0}"
        "Status.ExportErrorTitle" = "Export error"
        "Status.SelectRow" = "Select at least one row."
        "Status.LoginsCopied" = "Logins copied to the clipboard: {0}"
        "Status.ClipboardFailed" = "Could not copy to the clipboard: {0}"
        "Status.ReadyShort" = "Ready."
        "Status.Ready" = "Ready. Enter a domain/DC and login."
        "Status.LogCleared" = "Log cleared."
        "Status.LogEmpty" = "The log is empty."
        "Status.LogCopied" = "Log copied to the clipboard."
        "Status.LogCopyFailed" = "Could not copy the log: {0}"
        "Status.ValidationPasswordCleared" = "Validation password cleared."
        "Status.ChangeFieldsCleared" = "Password change fields cleared."
        "Status.EnterValidationData" = "Enter the domain/DC, login, and password to validate."
        "Status.ValidatingPassword" = "Validating the password for {0}\{1}..."
        "Status.PasswordValid" = "OK - the password is valid for {0}\{1}."
        "Status.PasswordInvalid" = "NOT OK - password validation failed."
        "Status.EnterDomainLogin" = "Enter the domain/DC and login."
        "Status.EnterPasswordChangeData" = "Enter the old password, new password, and repeat the new password."
        "Status.PasswordsDiffer" = "The new passwords do not match."
        "Status.PasswordUnchanged" = "The new password is the same as the old password."
        "Status.ConfirmPasswordChange" = "Change the password for {0}\{1}?`r`n`r`nThis operation uses the old and new password and does not perform an administrative reset."
        "Status.ConfirmPasswordChangeTitle" = "Confirm password change"
        "Status.PasswordChangeCancelled" = "Password change cancelled."
        "Status.ChangingPassword" = "Changing the password for {0}\{1}..."
        "Status.PasswordChanged" = "OK - the password has been changed for {0}\{1}."
        "Status.PasswordChangeError" = "Password change failed for {0}\{1}."
        "Status.EnterAccount" = "Enter the domain/DC and account login."
        "Status.GettingAccountProperties" = "Retrieving properties for {0}\{1}..."
        "Status.AccountPropertiesReceived" = "OK - properties retrieved: {0}."
        "Status.AccountPropertiesError" = "Error retrieving account properties: {0}"
        "Status.AccountPropertiesCleared" = "Account properties cleared."
        "Status.SelectProperties" = "Select properties to copy."
        "Status.PropertiesCopied" = "Selected properties copied: {0}."
        "Status.PropertiesCopyFailed" = "Could not copy properties: {0}"
        "Status.NoProperties" = "There are no account properties to copy."
        "Status.AllPropertiesCopied" = "All properties copied: {0}."
        "Status.GettingAccountGroups" = "Retrieving groups for {0}\{1}..."
        "Status.NoAccountGroups" = "OK - no groups found for {0}\{1}."
        "Status.AccountGroupsReceived" = "OK - account groups retrieved: {0}."
        "Status.AccountGroupsError" = "Error retrieving account groups: {0}"
        "Status.AccountGroupsCleared" = "Account group list cleared."
        "Status.SelectGroups" = "Select groups to copy."
        "Status.GroupsCopied" = "Selected groups copied: {0}."
        "Status.GroupsCopyFailed" = "Could not copy groups: {0}"
        "Status.NoAccountGroupsToCopy" = "There are no account groups to copy."
        "Status.AllGroupsCopied" = "All groups copied: {0}."
        "Status.EnterDomain" = "Enter the domain/DC."
        "Status.EnterGroup" = "Enter the domain group name."
        "Status.GettingGroupMembers" = "Retrieving members of {0}\{1}..."
        "Status.NoGroupMembers" = "OK - {0}\{1} has no direct members or they could not be retrieved."
        "Status.GroupMembersReceived" = "OK - group members retrieved: {0}."
        "Status.GroupMembersError" = "Error retrieving group members: {0}"
        "Status.GroupMembersCleared" = "Group member list cleared."
        "Status.SelectGroupMembers" = "Select group members to copy."
        "Status.GroupMembersCopied" = "Selected group members copied: {0}."
        "Status.GroupMembersCopyFailed" = "Could not copy group members: {0}"
        "Status.NoGroupMembersToCopy" = "There are no group members to copy."
        "Status.AllGroupMembersCopied" = "All group members copied: {0}."
        "Status.EnterManager" = "Enter the domain/DC and the managing account login."
        "Status.GettingManagedGroups" = "Retrieving groups managed by {0}\{1}..."
        "Status.NoManagedGroups" = "OK - no groups managed by {0}\{1} were found."
        "Status.ManagedGroupsReceived" = "OK - managed groups found: {0}."
        "Status.ManagedGroupsError" = "Error retrieving managed groups: {0}"
        "Status.ManagedGroupsCleared" = "Managed groups list cleared."
        "Status.SelectManagedGroups" = "Select managed groups to copy."
        "Status.ManagedGroupsCopied" = "Selected managed groups copied: {0}."
        "Status.ManagedGroupsCopyFailed" = "Could not copy managed groups: {0}"
        "Status.NoManagedGroupsToCopy" = "There are no managed groups to copy."
        "Status.AllManagedGroupsCopied" = "All managed groups copied: {0}."
        "Status.FindingManagerAccounts" = "Searching for accounts managed by {0}\{1}..."
        "Status.NoManagerAccounts" = "OK - no accounts managed by {0}\{1} were found."
        "Status.ManagerAccountsReceived" = "OK - managed accounts found: {0}; shown: {1} ({2})."
        "Status.ManagerAccountsError" = "Error retrieving managed accounts: {0}"
        "Status.ManagerAccountsCleared" = "Managed account list cleared."
    }
}

function Get-UiText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [object[]]$Values = @()
    )

    $languageCode = $script:UiLanguage
    if ($languageCode -notin @("pl", "en")) { $languageCode = "pl" }

    $text = $Key
    if ($script:Translations.ContainsKey($languageCode) -and $script:Translations[$languageCode].ContainsKey($Key)) {
        $text = [string]$script:Translations[$languageCode][$Key]
    }
    elseif ($script:Translations["pl"].ContainsKey($Key)) {
        $text = [string]$script:Translations["pl"][$Key]
    }

    if ($null -ne $Values -and $Values.Count -gt 0) {
        return [string]::Format([System.Globalization.CultureInfo]::CurrentCulture, $text, [object[]]$Values)
    }
    return $text
}

$script:Theme = [PSCustomObject]@{
    Back        = [System.Drawing.Color]::FromArgb(245, 248, 252)
    Card        = [System.Drawing.Color]::White
    Border      = [System.Drawing.Color]::FromArgb(215, 225, 235)
    Text        = [System.Drawing.Color]::FromArgb(35, 45, 60)
    Muted       = [System.Drawing.Color]::FromArgb(95, 105, 120)
    Navy        = [System.Drawing.Color]::FromArgb(13, 38, 82)
    Navy2       = [System.Drawing.Color]::FromArgb(0, 108, 210)
    Accent      = [System.Drawing.Color]::FromArgb(21, 121, 76)
    AccentDark  = [System.Drawing.Color]::FromArgb(12, 82, 55)
    Good        = [System.Drawing.Color]::FromArgb(0, 125, 60)
    Warn        = [System.Drawing.Color]::FromArgb(180, 105, 0)
    Bad         = [System.Drawing.Color]::FromArgb(190, 35, 35)
    HeaderText  = [System.Drawing.Color]::White
}

# ==================================================
# GUI helpers
# ==================================================

function New-UiFont {
    param(
        [single]$Size = 9.0,
        [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular
    )

    return New-Object System.Drawing.Font("Segoe UI", $Size, $Style)
}

function New-Point {
    param([int]$X, [int]$Y)
    return New-Object System.Drawing.Point($X, $Y)
}

function New-Size {
    param([int]$W, [int]$H)
    return New-Object System.Drawing.Size($W, $H)
}

function Set-DoubleBuffered {
    param($Control)

    if ($null -eq $Control) { return }

    try {
        $flags = [System.Reflection.BindingFlags] "Instance, NonPublic"
        $prop = $Control.GetType().GetProperty("DoubleBuffered", $flags)
        if ($null -ne $prop) { $prop.SetValue($Control, $true, $null) }
    }
    catch { }
}


function Get-AppWindowIcon {
    <#
        A WinForms window does not always inherit the icon set by ps2exe -IconFile.
        That parameter sets the EXE file icon, while the form still requires
        an explicit $form.Icon value.

        Lookup order:
        1. known kombajn*.ico files next to the script/EXE,
        2. the icon embedded in the running EXE by ps2exe -IconFile.
    #>

    $candidates = New-Object System.Collections.ArrayList

    try {
        if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
            [void]$candidates.Add((Join-Path $PSScriptRoot "kombajn1.ico"))
            [void]$candidates.Add((Join-Path $PSScriptRoot "kombajn2.ico"))
            [void]$candidates.Add((Join-Path $PSScriptRoot "kombajn3.ico"))
        }
    }
    catch { }

    try {
        $exeDir = [System.IO.Path]::GetDirectoryName([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
        if (-not [string]::IsNullOrWhiteSpace($exeDir)) {
            [void]$candidates.Add((Join-Path $exeDir "kombajn1.ico"))
            [void]$candidates.Add((Join-Path $exeDir "kombajn2.ico"))
            [void]$candidates.Add((Join-Path $exeDir "kombajn3.ico"))
        }
    }
    catch { }

    foreach ($candidate in $candidates) {
        try {
            if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
            if (-not (Test-Path -LiteralPath $candidate)) { continue }

            $fs = [System.IO.File]::Open($candidate, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            try {
                $ico = New-Object System.Drawing.Icon($fs)
                return $ico.Clone()
            }
            finally {
                $fs.Dispose()
            }
        }
        catch { }
    }

    try {
        $exePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if (-not [string]::IsNullOrWhiteSpace($exePath) -and (Test-Path -LiteralPath $exePath)) {
            return [System.Drawing.Icon]::ExtractAssociatedIcon($exePath)
        }
    }
    catch { }

    return $null
}

function Apply-AppWindowIcon {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.Form]$Form
    )

    try {
        if ($null -eq $script:AppWindowIcon) {
            $script:AppWindowIcon = Get-AppWindowIcon
        }

        if ($null -ne $script:AppWindowIcon) {
            $Form.Icon = $script:AppWindowIcon
        }
    }
    catch { }
}

function Select-UiLanguage {
    if ($script:UiLanguage -in @("pl", "en")) { return $true }

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "ADKombajn - Language / Język"
    $dialog.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $dialog.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.ShowInTaskbar = $true
    $dialog.ClientSize = New-Size 430 172
    $dialog.BackColor = $script:Theme.Back
    Apply-AppWindowIcon $dialog

    $title = New-Object System.Windows.Forms.Label
    $title.Text = "Choose interface language / Wybierz język interfejsu"
    $title.Location = New-Point 20 20
    $title.Size = New-Size 390 28
    $title.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $title.Font = New-UiFont 10.5 ([System.Drawing.FontStyle]::Bold)
    $title.ForeColor = $script:Theme.Text

    $btnPolish = New-FlatButton "Polski" 52 76 145 44
    $btnEnglish = New-FlatButton "English" 232 76 145 44

    $btnPolish.Add_Click({
        $script:UiLanguage = "pl"
        $dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
    })
    $btnEnglish.Add_Click({
        $script:UiLanguage = "en"
        $dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
    })

    $dialog.Controls.AddRange(@($title, $btnPolish, $btnEnglish))
    try {
        [void]$dialog.ShowDialog()
    }
    finally {
        $dialog.Dispose()
    }

    return ($script:UiLanguage -in @("pl", "en"))
}

function New-FlatButton {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$W = 120,
        [int]$H = 32,
        [System.Drawing.Color]$BackColor = $script:Theme.Accent,
        [System.Drawing.Color]$ForeColor = [System.Drawing.Color]::White
    )

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Location = New-Point $X $Y
    $btn.Size = New-Size $W $H
    $btn.Font = New-UiFont 9 ([System.Drawing.FontStyle]::Bold)
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderSize = 1
    $btn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(174, 229, 199)
    $btn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(35, 145, 94)
    $btn.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(12, 82, 55)
    $btn.BackColor = $BackColor
    $btn.ForeColor = $ForeColor
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btn.UseVisualStyleBackColor = $false
    return $btn
}

function New-SoftButton {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$W = 120,
        [int]$H = 32
    )

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Location = New-Point $X $Y
    $btn.Size = New-Size $W $H
    $btn.Font = New-UiFont 9 ([System.Drawing.FontStyle]::Regular)
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderColor = $script:Theme.Border
    $btn.BackColor = [System.Drawing.Color]::White
    $btn.ForeColor = $script:Theme.Text
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    return $btn
}

function New-Label {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$W = 100,
        [int]$H = 24,
        [single]$FontSize = 9.0,
        [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular
    )

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Text
    $lbl.Location = New-Point $X $Y
    $lbl.Size = New-Size $W $H
    $lbl.Font = New-UiFont $FontSize $Style
    $lbl.ForeColor = $script:Theme.Text
    return $lbl
}

function New-TextBoxEx {
    param(
        [int]$X,
        [int]$Y,
        [int]$W = 240,
        [bool]$Password = $false
    )

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location = New-Point $X $Y
    $txt.Width = $W
    $txt.Font = New-UiFont 9.5
    $txt.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $txt.UseSystemPasswordChar = $Password
    return $txt
}

function New-CardGroup {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$W,
        [int]$H
    )

    $grp = New-Object System.Windows.Forms.GroupBox
    $grp.Text = $Text
    $grp.Location = New-Point $X $Y
    $grp.Size = New-Size $W $H
    $grp.Font = New-UiFont 9 ([System.Drawing.FontStyle]::Bold)
    $grp.ForeColor = $script:Theme.Text
    $grp.BackColor = $script:Theme.Card
    return $grp
}

function Write-Log {
    param(
        [string]$Text,
        [ValidateSet("INFO", "OK", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )

    $stamp = Get-Date -Format "HH:mm:ss"
    $line = "[$stamp][$Level] $Text"

    try {
        $targets = @()
        if ($null -ne $script:txtLogs -and @($script:txtLogs).Count -gt 0) {
            $targets = @($script:txtLogs)
        }
        elseif ($null -ne $script:txtLog) {
            $targets = @($script:txtLog)
        }

        foreach ($logBox in $targets) {
            if ($null -ne $logBox -and -not $logBox.IsDisposed) {
                $logBox.AppendText($line + [Environment]::NewLine)
                $logBox.SelectionStart = $logBox.TextLength
                $logBox.ScrollToCaret()
            }
        }
    }
    catch { }
}

function Set-Status {
    param(
        [string]$Text,
        [ValidateSet("Info", "Ok", "Warn", "Error")]
        [string]$Kind = "Info",
        [bool]$ToLog = $true
    )

    $color = $script:Theme.Text
    $level = "INFO"

    switch ($Kind) {
        "Ok"    { $color = $script:Theme.Good; $level = "OK" }
        "Warn"  { $color = $script:Theme.Warn; $level = "WARN" }
        "Error" { $color = $script:Theme.Bad;  $level = "ERROR" }
        default  { $color = $script:Theme.Text; $level = "INFO" }
    }

    try {
        if ($null -ne $script:StatusLabel) {
            $script:StatusLabel.Text = $Text
            $script:StatusLabel.ForeColor = $color
        }
    }
    catch { }

    if ($ToLog) { Write-Log -Text $Text -Level $level }
    try { [System.Windows.Forms.Application]::DoEvents() } catch { }
}

function Show-InfoBox {
    param([string]$Text, [string]$Title = $script:AppName)
    [void][System.Windows.Forms.MessageBox]::Show($Text, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
}

function Show-ErrorBox {
    param([string]$Text, [string]$Title = $script:AppName)
    [void][System.Windows.Forms.MessageBox]::Show($Text, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
}

function Show-BusyProgressWindow {
    param(
        [string]$Title = (Get-UiText "Busy.Title"),
        [string]$Message = (Get-UiText "Busy.Message"),
        [string]$Detail = (Get-UiText "Busy.Detail"),
        [int]$Width = 470
    )

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = $Title
    $dlg.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.ControlBox = $false
    $dlg.ShowInTaskbar = $false
    $dlg.TopMost = $false
    $dlg.BackColor = $script:Theme.Back
    $dlg.ClientSize = New-Object System.Drawing.Size($Width, 145)

    try {
        if ($null -ne $script:AppWindowIcon) { $dlg.Icon = $script:AppWindowIcon }
    }
    catch { }

    $outer = New-Object System.Windows.Forms.Panel
    $outer.Location = New-Object System.Drawing.Point(12, 12)
    $outer.Size = New-Object System.Drawing.Size(($Width - 24), 121)
    $outer.BackColor = $script:Theme.Card
    $outer.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.AutoSize = $false
    $lblTitle.Location = New-Object System.Drawing.Point(18, 14)
    $lblTitle.Size = New-Object System.Drawing.Size(($Width - 60), 24)
    $lblTitle.Text = $Message
    $lblTitle.Font = New-UiFont 10.0 ([System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = $script:Theme.Text

    $lblDetail = New-Object System.Windows.Forms.Label
    $lblDetail.AutoSize = $false
    $lblDetail.Location = New-Object System.Drawing.Point(18, 40)
    $lblDetail.Size = New-Object System.Drawing.Size(($Width - 60), 22)
    $lblDetail.Text = $Detail
    $lblDetail.Font = New-UiFont 8.8 ([System.Drawing.FontStyle]::Regular)
    $lblDetail.ForeColor = $script:Theme.Muted

    $progress = New-Object System.Windows.Forms.ProgressBar
    $progress.Location = New-Object System.Drawing.Point(18, 76)
    $progress.Size = New-Object System.Drawing.Size(($Width - 60), 18)
    $progress.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
    $progress.MarqueeAnimationSpeed = 28

    $lblWait = New-Object System.Windows.Forms.Label
    $lblWait.AutoSize = $false
    $lblWait.Location = New-Object System.Drawing.Point(18, 98)
    $lblWait.Size = New-Object System.Drawing.Size(($Width - 60), 18)
    $lblWait.Text = Get-UiText "Busy.DoNotClose"
    $lblWait.Font = New-UiFont 8.0 ([System.Drawing.FontStyle]::Italic)
    $lblWait.ForeColor = $script:Theme.Muted

    $outer.Controls.AddRange(@($lblTitle, $lblDetail, $progress, $lblWait))
    $dlg.Controls.Add($outer)

    try {
        if ($null -ne $script:MainForm -and -not $script:MainForm.IsDisposed) {
            [void]$dlg.Show($script:MainForm)
        }
        else {
            [void]$dlg.Show()
        }
        $dlg.Refresh()
        [System.Windows.Forms.Application]::DoEvents()
    }
    catch { }

    try {
        $dlg | Add-Member -MemberType NoteProperty -Name BusyProgressBar -Value $progress -Force
        $dlg | Add-Member -MemberType NoteProperty -Name BusyDetailLabel -Value $lblDetail -Force
        $dlg | Add-Member -MemberType NoteProperty -Name BusyTitleLabel -Value $lblTitle -Force
    }
    catch { }

    return $dlg
}

function Set-BusyProgressWindow {
    param(
        $ProgressWindow,
        [string]$Message,
        [string]$Detail,
        [int]$Value = -1,
        [int]$Maximum = -1,
        [bool]$Marquee = $false
    )

    try {
        if ($null -eq $ProgressWindow -or $ProgressWindow.IsDisposed) { return }

        if (-not (Is-Blank $Message) -and $null -ne $ProgressWindow.BusyTitleLabel) {
            $ProgressWindow.BusyTitleLabel.Text = $Message
        }

        if (-not (Is-Blank $Detail) -and $null -ne $ProgressWindow.BusyDetailLabel) {
            $ProgressWindow.BusyDetailLabel.Text = $Detail
        }

        if ($null -ne $ProgressWindow.BusyProgressBar) {
            if ($Marquee) {
                $ProgressWindow.BusyProgressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
                $ProgressWindow.BusyProgressBar.MarqueeAnimationSpeed = 28
            }
            elseif ($Maximum -gt 0) {
                $ProgressWindow.BusyProgressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
                $ProgressWindow.BusyProgressBar.MarqueeAnimationSpeed = 0
                $ProgressWindow.BusyProgressBar.Minimum = 0
                $ProgressWindow.BusyProgressBar.Maximum = $Maximum
                if ($Value -lt 0) { $Value = 0 }
                if ($Value -gt $Maximum) { $Value = $Maximum }
                $ProgressWindow.BusyProgressBar.Value = $Value
            }
        }

        $ProgressWindow.Refresh()
        [System.Windows.Forms.Application]::DoEvents()
    }
    catch { }
}

function Close-BusyProgressWindow {
    param($ProgressWindow)

    try {
        if ($null -ne $ProgressWindow -and -not $ProgressWindow.IsDisposed) {
            $ProgressWindow.Close()
            $ProgressWindow.Dispose()
            [System.Windows.Forms.Application]::DoEvents()
        }
    }
    catch { }
}

# ==================================================
# Splash
# ==================================================

function New-RoundedRectanglePath {
    param(
        [System.Drawing.Rectangle]$Rect,
        [int]$Radius
    )

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $diameter = $Radius * 2

    if ($diameter -le 0) {
        [void]$path.AddRectangle($Rect)
        return $path
    }

    $arc = New-Object System.Drawing.Rectangle($Rect.X, $Rect.Y, $diameter, $diameter)
    [void]$path.AddArc($arc, 180, 90)
    $arc.X = $Rect.Right - $diameter
    [void]$path.AddArc($arc, 270, 90)
    $arc.Y = $Rect.Bottom - $diameter
    [void]$path.AddArc($arc, 0, 90)
    $arc.X = $Rect.X
    [void]$path.AddArc($arc, 90, 90)
    [void]$path.CloseFigure()
    return $path
}

function Show-WinSplash {
    param(
        [int]$Milliseconds = 1600,
        [string]$Title = "ADKombajn",
        [string]$Subtitle = (Get-UiText "Splash.Subtitle"),
        [string]$Version = $script:AppVersion,
        [string]$Author = (Get-UiText "Splash.Author" @($script:AppAuthor))
    )

    $splash = $null
    $splashPicture = $null

    try {
        $totalMs = [Math]::Max(700, [int]$Milliseconds)
        $greenDark = [System.Drawing.Color]::FromArgb(18, 66, 55)
        $green = [System.Drawing.Color]::FromArgb(38, 145, 94)
        $softGreen = [System.Drawing.Color]::FromArgb(222, 245, 232)
        $mutedGreen = [System.Drawing.Color]::FromArgb(196, 231, 212)

        $splash = New-Object System.Windows.Forms.Form
        $splash.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
        $splash.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
        $splash.ClientSize = New-Size 700 360
        $splash.BackColor = $greenDark
        $splash.ShowInTaskbar = $false
        $splash.TopMost = $true
        $splash.Opacity = 0.0
        $splash.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
        Set-DoubleBuffered $splash
        Apply-AppWindowIcon $splash

        $splash.Add_Paint({
            param($sender, $e)

            if ($sender.ClientRectangle.Width -le 0 -or $sender.ClientRectangle.Height -le 0) { return }

            $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush -ArgumentList @(
                $sender.ClientRectangle,
                $greenDark,
                $green,
                [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal
            )
            try {
                $e.Graphics.FillRectangle($brush, $sender.ClientRectangle)
            }
            finally {
                $brush.Dispose()
            }
        })

        $splashPicture = New-Object System.Windows.Forms.PictureBox
        $splashPicture.Location = New-Point 26 48
        $splashPicture.Size = New-Size 300 190
        $splashPicture.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
        $splashPicture.BackColor = [System.Drawing.Color]::Transparent
        $splashPicture.Image = $script:BrandImage
        $splashPicture.TabStop = $false
        [void]$splash.Controls.Add($splashPicture)

        $splashTitle = New-Object System.Windows.Forms.Label
        $splashTitle.Text = $Title
        $splashTitle.ForeColor = [System.Drawing.Color]::White
        $splashTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 30)
        $splashTitle.AutoSize = $true
        $splashTitle.Location = New-Point 350 78
        $splashTitle.BackColor = [System.Drawing.Color]::Transparent
        [void]$splash.Controls.Add($splashTitle)

        $splashSubtitle = New-Object System.Windows.Forms.Label
        $splashSubtitle.Text = $Subtitle
        $splashSubtitle.ForeColor = $softGreen
        $splashSubtitle.Font = New-Object System.Drawing.Font("Segoe UI", 11)
        $splashSubtitle.AutoSize = $true
        $splashSubtitle.Location = New-Point 354 139
        $splashSubtitle.BackColor = [System.Drawing.Color]::Transparent
        [void]$splash.Controls.Add($splashSubtitle)

        $splashVersion = New-Object System.Windows.Forms.Label
        $splashVersion.Text = Get-UiText "Splash.Version" @($Version)
        $splashVersion.ForeColor = [System.Drawing.Color]::White
        $splashVersion.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
        $splashVersion.AutoSize = $true
        $splashVersion.Location = New-Point 354 184
        $splashVersion.BackColor = [System.Drawing.Color]::Transparent
        [void]$splash.Controls.Add($splashVersion)

        $splashAuthor = New-Object System.Windows.Forms.Label
        $splashAuthor.Text = $Author
        $splashAuthor.ForeColor = $mutedGreen
        $splashAuthor.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $splashAuthor.AutoSize = $true
        $splashAuthor.Location = New-Point 354 209
        $splashAuthor.BackColor = [System.Drawing.Color]::Transparent
        [void]$splash.Controls.Add($splashAuthor)

        $barBack = New-Object System.Windows.Forms.Panel
        $barBack.Location = New-Point 30 300
        $barBack.Size = New-Size 640 8
        $barBack.BackColor = [System.Drawing.Color]::FromArgb(13, 74, 55)
        [void]$splash.Controls.Add($barBack)

        $barFill = New-Object System.Windows.Forms.Panel
        $barFill.Location = New-Point 0 0
        $barFill.Size = New-Size 12 8
        $barFill.BackColor = [System.Drawing.Color]::FromArgb(92, 225, 148)
        [void]$barBack.Controls.Add($barFill)

        $splashStatus = New-Object System.Windows.Forms.Label
        $splashStatus.Text = Get-UiText "Splash.Loading"
        $splashStatus.ForeColor = $softGreen
        $splashStatus.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $splashStatus.AutoSize = $true
        $splashStatus.Location = New-Point 30 318
        $splashStatus.BackColor = [System.Drawing.Color]::Transparent
        [void]$splash.Controls.Add($splashStatus)

        $splash.Show()
        $splash.Activate()
        [System.Windows.Forms.Application]::DoEvents()

        $step = 25
        $elapsed = 0
        while ($elapsed -lt $totalMs) {
            $progress = [Math]::Min(1.0, ([double]$elapsed / [double]$totalMs))
            $barFill.Width = [int]([Math]::Max(12.0, [double]$barBack.Width * $progress))

            if ($elapsed -lt 250) {
                $splash.Opacity = [Math]::Min(1.0, ([double]$elapsed / 250.0))
            }
            elseif ($elapsed -gt ($totalMs - 280)) {
                $remaining = [Math]::Max(0, ($totalMs - $elapsed))
                $splash.Opacity = [Math]::Max(0.0, ([double]$remaining / 280.0))
            }
            else {
                $splash.Opacity = 1.0
            }

            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds $step
            $elapsed += $step
        }
    }
    catch { }
    finally {
        if ($null -ne $splashPicture) { $splashPicture.Image = $null }
        if ($null -ne $splash -and -not $splash.IsDisposed) {
            $splash.Close()
            [System.Windows.Forms.Application]::DoEvents()
            $splash.Dispose()
        }
    }
}

# ==================================================
# AD / LDAP tools
# ==================================================

function Is-Blank {
    param($Value)
    if ($null -eq $Value) { return $true }
    return ([string]$Value).Trim().Length -eq 0
}

function Escape-LdapFilterValue {
    param([string]$Value)
    if ($null -eq $Value) { return "" }

    $escaped = $Value.Replace('\', '\5c')
    $escaped = $escaped.Replace('*', '\2a')
    $escaped = $escaped.Replace('(', '\28')
    $escaped = $escaped.Replace(')', '\29')
    $escaped = $escaped.Replace(([string][char]0), '\00')
    return $escaped
}

function Get-SearchPropertyValue {
    param(
        $Properties,
        [string]$Name
    )

    if ($null -eq $Properties -or (Is-Blank $Name)) { return "" }

    try {
        $matchingKey = $null
        foreach ($propertyName in $Properties.PropertyNames) {
            if ($propertyName -ieq $Name) {
                $matchingKey = $propertyName
                break
            }
        }

        if ($null -ne $matchingKey -and $Properties[$matchingKey].Count -gt 0 -and $null -ne $Properties[$matchingKey][0]) {
            return $Properties[$matchingKey][0]
        }
    }
    catch { }

    return ""
}

function Convert-ADFileTimeToText {
    param($Value)

    try {
        if ($null -eq $Value) { return "" }
        $raw = $Value

        if ($Value -is [System.Collections.ICollection]) {
            if ($Value.Count -gt 0) { $raw = $Value[0] } else { return "" }
        }

        if ($null -eq $raw) { return "" }
        $fileTime = [Int64]$raw
        if ($fileTime -le 0) { return "" }
        return [DateTime]::FromFileTime($fileTime).ToString("yyyy-MM-dd HH:mm:ss")
    }
    catch { return "" }
}

function Convert-UserAccountControlToEnabled {
    param($Value)

    try {
        if ($null -eq $Value -or (Is-Blank $Value)) { return "" }
        $uac = [int]$Value
        if (($uac -band 2) -eq 2) { return "False" }
        return "True"
    }
    catch { return "" }
}

function Get-LdapBasePath {
    param([string]$DomainOrDc)

    $rootDse = $null
    try {
        $rootDse = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$DomainOrDc/RootDSE")
        $defaultNamingContext = [string]$rootDse.Properties["defaultNamingContext"].Value
        if (-not (Is-Blank $defaultNamingContext)) {
            return "LDAP://$DomainOrDc/$defaultNamingContext"
        }
    }
    finally {
        if ($null -ne $rootDse) { $rootDse.Dispose() }
    }

    return "LDAP://$DomainOrDc"
}

function Get-LdapPortFromUi {
    if ($chkUseLdaps.Checked) { return 636 }
    return 389
}

function New-LdapConnectionCurrentUser {
    param(
        [string]$Server,
        [bool]$UseLdaps = $false,
        [int]$Port = 389
    )

    $identifier = New-Object System.DirectoryServices.Protocols.LdapDirectoryIdentifier -ArgumentList $Server, $Port, $false, $false
    $connection = New-Object System.DirectoryServices.Protocols.LdapConnection -ArgumentList $identifier
    $connection.AuthType = [System.DirectoryServices.Protocols.AuthType]::Negotiate
    $connection.Timeout = New-TimeSpan -Seconds 35
    $connection.SessionOptions.ProtocolVersion = 3

    if ($UseLdaps) {
        $connection.SessionOptions.SecureSocketLayer = $true
    }
    else {
        # Encrypted SASL channel over port 389, so unicodePwd changes do not require LDAPS.
        $connection.SessionOptions.Signing = $true
        $connection.SessionOptions.Sealing = $true
    }

    $connection.Bind()
    return $connection
}

function New-LdapConnectionWithCredentials {
    param(
        [string]$Server,
        [string]$Domain,
        [string]$Login,
        [string]$Password,
        [bool]$UseLdaps = $false,
        [int]$Port = 389
    )

    $identifier = New-Object System.DirectoryServices.Protocols.LdapDirectoryIdentifier -ArgumentList $Server, $Port, $false, $false
    $connection = New-Object System.DirectoryServices.Protocols.LdapConnection -ArgumentList $identifier
    $connection.AuthType = [System.DirectoryServices.Protocols.AuthType]::Negotiate
    $connection.Timeout = New-TimeSpan -Seconds 20
    $connection.SessionOptions.ProtocolVersion = 3

    if ($UseLdaps) {
        $connection.SessionOptions.SecureSocketLayer = $true
    }
    else {
        $connection.SessionOptions.Signing = $true
        $connection.SessionOptions.Sealing = $true
    }

    if ($Login -match "^([^\\]+)\\(.+)$") {
        $cred = New-Object System.Net.NetworkCredential($Matches[2], $Password, $Matches[1])
    }
    elseif ($Login -match "@") {
        $cred = New-Object System.Net.NetworkCredential($Login, $Password)
    }
    else {
        $cred = New-Object System.Net.NetworkCredential($Login, $Password, $Domain)
    }

    $connection.Bind($cred)
    return $connection
}

function Convert-ToUnicodePwdBytes {
    param([Parameter(Mandatory = $true)][string]$Password)

    # AD expects the password in quotation marks and UTF-16LE.
    # The comma before $bytes is important: without it PowerShell may expand byte[]
    # to System.Object[], causing DirectoryAttributeModification.Add() to choose
    # an incorrect overload and fail with a System.Uri/System.Object[] error.
    [byte[]]$bytes = [System.Text.Encoding]::Unicode.GetBytes('"' + $Password + '"')
    return ,$bytes
}
function Get-FriendlyLdapError {
    param([System.Exception]$Exception)

    $message = $Exception.Message
    $code = ""

    if ($Exception -is [System.DirectoryServices.Protocols.DirectoryOperationException]) {
        $resp = $Exception.Response
        if ($null -ne $resp) {
            $code = [string]$resp.ResultCode
            if (-not (Is-Blank $resp.ErrorMessage)) { $message = $resp.ErrorMessage }
        }
    }
    elseif ($Exception -is [System.DirectoryServices.Protocols.LdapException]) {
        $code = [string]$Exception.ErrorCode
    }

    $hint = ""
    $lower = $message.ToLowerInvariant()

    if ($lower -match "constraint|unwilling|0000052d|52d") {
        $hint = Get-UiText "Ldap.HintPasswordPolicy"
    }
    elseif ($lower -match "invalid credentials|52e|775|data 52e") {
        $hint = Get-UiText "Ldap.HintCredentials"
    }
    elseif ($lower -match "server is unavailable|cannot contact|unavailable") {
        $hint = Get-UiText "Ldap.HintConnection"
    }
    elseif ($lower -match "confidentiality|required|stronger") {
        $hint = Get-UiText "Ldap.HintSecureChannel"
    }

    if (-not (Is-Blank $code)) {
        $codeText = Get-UiText "Ldap.Code" @($code)
        $message = "$message`r`n$codeText"
    }
    if (-not (Is-Blank $hint)) {
        $hintText = Get-UiText "Ldap.Hint" @($hint)
        $message = "$message`r`n`r`n$hintText"
    }

    return $message
}

function Find-AdUserBasic {
    param(
        [string]$DomainOrDc,
        [string]$Login
    )

    $ldapBasePath = Get-LdapBasePath -DomainOrDc $DomainOrDc
    $root = $null
    $searcher = $null
    $result = $null

    try {
        $root = New-Object System.DirectoryServices.DirectoryEntry($ldapBasePath)
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($root)
        $searcher.SearchScope = [System.DirectoryServices.SearchScope]::Subtree
        $searcher.PageSize = 1000

        $escaped = Escape-LdapFilterValue -Value $Login
        if ($Login -match "@") {
            $searcher.Filter = "(&(objectCategory=person)(objectClass=user)(|(userPrincipalName=$escaped)(sAMAccountName=$escaped)))"
        }
        else {
            $searcher.Filter = "(&(objectCategory=person)(objectClass=user)(sAMAccountName=$escaped))"
        }

        foreach ($p in @("sAMAccountName", "name", "displayName", "userPrincipalName", "distinguishedName", "description", "userAccountControl", "pwdLastSet")) {
            [void]$searcher.PropertiesToLoad.Add($p)
        }

        $result = $searcher.FindOne()
        if ($null -eq $result) { return $null }

        $props = $result.Properties
        $dn = [string](Get-SearchPropertyValue -Properties $props -Name "distinguishedName")
        $sam = [string](Get-SearchPropertyValue -Properties $props -Name "sAMAccountName")
        $uac = Get-SearchPropertyValue -Properties $props -Name "userAccountControl"
        $pwd = Get-SearchPropertyValue -Properties $props -Name "pwdLastSet"

        return [PSCustomObject]@{
            SamAccountName    = $sam
            Name              = [string](Get-SearchPropertyValue -Properties $props -Name "name")
            DisplayName       = [string](Get-SearchPropertyValue -Properties $props -Name "displayName")
            UserPrincipalName = [string](Get-SearchPropertyValue -Properties $props -Name "userPrincipalName")
            Description       = [string](Get-SearchPropertyValue -Properties $props -Name "description")
            Enabled           = Convert-UserAccountControlToEnabled -Value $uac
            PasswordLastSet   = Convert-ADFileTimeToText -Value $pwd
            DistinguishedName = $dn
        }
    }
    finally {
        if ($null -ne $searcher) { $searcher.Dispose() }
        if ($null -ne $root) { $root.Dispose() }
    }
}

function Test-AdPasswordNoRsat {
    param(
        [string]$DomainOrDc,
        [string]$Login,
        [string]$Password,
        [bool]$UseLdaps = $false,
        [int]$Port = 389
    )

    # Password validation intentionally follows the simple validPassword.ps1 approach:
    # PrincipalContext.ValidateCredentials().
    # Password changes still use LDAP unicodePwd without UserPrincipal.ChangePassword().
    # UseLdaps/Port remain in the signature for GUI compatibility, while
    # ValidateCredentials selects the domain/controller connection mechanism itself.

    $context = $null

    try {
        Add-Type -AssemblyName System.DirectoryServices.AccountManagement

        $loginToValidate = $Login.Trim()

        # Strip the domain prefix from DOMAIN\login because ValidateCredentials
        # in a domain context normally expects a login name or UPN.
        if ($loginToValidate -match "^[^\\]+\\(.+)$") {
            $loginToValidate = $Matches[1]
        }

        $context = New-Object System.DirectoryServices.AccountManagement.PrincipalContext(
            [System.DirectoryServices.AccountManagement.ContextType]::Domain,
            $DomainOrDc
        )

        $ok = $context.ValidateCredentials($loginToValidate, $Password)

        if ($ok) {
            return [PSCustomObject]@{ Success = $true; Message = (Get-UiText "Password.Valid") }
        }

        return [PSCustomObject]@{
            Success = $false
            Message = Get-UiText "Password.Invalid"
        }
    }
    catch {
        return [PSCustomObject]@{ Success = $false; Message = Get-FriendlyLdapError -Exception $_.Exception }
    }
    finally {
        if ($null -ne $context) { $context.Dispose() }
    }
}
function Change-AdAccountPasswordNoRsat {
    param(
        [string]$DomainOrDc,
        [string]$Login,
        [string]$OldPassword,
        [string]$NewPassword,
        [bool]$UseLdaps = $false,
        [int]$Port = 389
    )

    $connection = $null
    $oldBytes = $null
    $newBytes = $null

    try {
        $target = Find-AdUserBasic -DomainOrDc $DomainOrDc -Login $Login
        if ($null -eq $target -or (Is-Blank $target.DistinguishedName)) {
            throw (Get-UiText "Error.AccountNotFound" @($DomainOrDc, $Login))
        }

        $connection = New-LdapConnectionCurrentUser -Server $DomainOrDc -UseLdaps $UseLdaps -Port $Port

        $oldBytes = Convert-ToUnicodePwdBytes -Password $OldPassword
        $newBytes = Convert-ToUnicodePwdBytes -Password $NewPassword

        $deleteOld = New-Object System.DirectoryServices.Protocols.DirectoryAttributeModification
        $deleteOld.Name = "unicodePwd"
        $deleteOld.Operation = [System.DirectoryServices.Protocols.DirectoryAttributeOperation]::Delete
        [void]$deleteOld.Add([byte[]]$oldBytes)

        $addNew = New-Object System.DirectoryServices.Protocols.DirectoryAttributeModification
        $addNew.Name = "unicodePwd"
        $addNew.Operation = [System.DirectoryServices.Protocols.DirectoryAttributeOperation]::Add
        [void]$addNew.Add([byte[]]$newBytes)

        $request = New-Object System.DirectoryServices.Protocols.ModifyRequest
        $request.DistinguishedName = $target.DistinguishedName
        [void]$request.Modifications.Add($deleteOld)
        [void]$request.Modifications.Add($addNew)

        $response = $connection.SendRequest($request)

        return [PSCustomObject]@{
            Success = $true
            Message = Get-UiText "Password.Changed"
            Result  = [string]$response.ResultCode
            Target  = $target
        }
    }
    catch {
        return [PSCustomObject]@{
            Success = $false
            Message = Get-FriendlyLdapError -Exception $_.Exception
            Result  = $_.Exception.GetType().FullName
            Target  = $null
        }
    }
    finally {
        if ($null -ne $connection) { $connection.Dispose() }
        if ($null -ne $oldBytes) { [Array]::Clear($oldBytes, 0, $oldBytes.Length) }
        if ($null -ne $newBytes) { [Array]::Clear($newBytes, 0, $newBytes.Length) }
        $oldBytes = $null
        $newBytes = $null
    }
}


function Convert-UserAccountControlToFlagsText {
    param($Value)

    try {
        if ($null -eq $Value -or (Is-Blank $Value)) { return "" }
        $uac = [int]$Value
        $flags = @()
        $map = @(
            @{ Bit = 0x0001; Name = "SCRIPT" },
            @{ Bit = 0x0002; Name = "ACCOUNTDISABLE" },
            @{ Bit = 0x0008; Name = "HOMEDIR_REQUIRED" },
            @{ Bit = 0x0010; Name = "LOCKOUT" },
            @{ Bit = 0x0020; Name = "PASSWD_NOTREQD" },
            @{ Bit = 0x0040; Name = "PASSWD_CANT_CHANGE" },
            @{ Bit = 0x0080; Name = "ENCRYPTED_TEXT_PWD_ALLOWED" },
            @{ Bit = 0x0100; Name = "TEMP_DUPLICATE_ACCOUNT" },
            @{ Bit = 0x0200; Name = "NORMAL_ACCOUNT" },
            @{ Bit = 0x0800; Name = "INTERDOMAIN_TRUST_ACCOUNT" },
            @{ Bit = 0x1000; Name = "WORKSTATION_TRUST_ACCOUNT" },
            @{ Bit = 0x2000; Name = "SERVER_TRUST_ACCOUNT" },
            @{ Bit = 0x10000; Name = "DONT_EXPIRE_PASSWORD" },
            @{ Bit = 0x20000; Name = "MNS_LOGON_ACCOUNT" },
            @{ Bit = 0x40000; Name = "SMARTCARD_REQUIRED" },
            @{ Bit = 0x80000; Name = "TRUSTED_FOR_DELEGATION" },
            @{ Bit = 0x100000; Name = "NOT_DELEGATED" },
            @{ Bit = 0x200000; Name = "USE_DES_KEY_ONLY" },
            @{ Bit = 0x400000; Name = "DONT_REQ_PREAUTH" },
            @{ Bit = 0x800000; Name = "PASSWORD_EXPIRED" },
            @{ Bit = 0x1000000; Name = "TRUSTED_TO_AUTH_FOR_DELEGATION" },
            @{ Bit = 0x04000000; Name = "PARTIAL_SECRETS_ACCOUNT" }
        )

        foreach ($item in $map) {
            if (($uac -band [int]$item.Bit) -ne 0) { $flags += [string]$item.Name }
        }

        if ($flags.Count -eq 0) { return [string]$uac }
        return ("{0} ({1})" -f $uac, ($flags -join ", "))
    }
    catch { return [string]$Value }
}

function Convert-ComputedUserAccountControlToFlagsText {
    param($Value)

    try {
        if ($null -eq $Value -or (Is-Blank $Value)) { return "" }
        $uac = [int]$Value
        $flags = @()
        $map = @(
            @{ Bit = 0x00000010; Name = "LOCKOUT" },
            @{ Bit = 0x00800000; Name = "PASSWORD_EXPIRED" }
        )

        foreach ($item in $map) {
            if (($uac -band [int]$item.Bit) -ne 0) { $flags += [string]$item.Name }
        }

        if ($flags.Count -eq 0) { return [string]$uac }
        return ("{0} ({1})" -f $uac, ($flags -join ", "))
    }
    catch { return [string]$Value }
}

function Convert-ADFileTimeToReadableText {
    param(
        $Value,
        [string]$ZeroText = ""
    )

    try {
        if ($null -eq $Value) { return "" }
        $raw = $Value

        if ($Value -is [System.Collections.ICollection]) {
            if ($Value.Count -gt 0) { $raw = $Value[0] } else { return "" }
        }

        if ($null -eq $raw) { return "" }
        $fileTime = [Int64]$raw
        if ($fileTime -le 0) {
            if (-not (Is-Blank $ZeroText)) { return $ZeroText }
            return [string]$fileTime
        }

        return [DateTime]::FromFileTime($fileTime).ToString("yyyy-MM-dd HH:mm:ss")
    }
    catch { return [string]$Value }
}

function Convert-ADAccountExpiresToText {
    param($Value)

    try {
        if ($null -eq $Value -or (Is-Blank $Value)) { return "" }
        $raw = [Int64]$Value
        if ($raw -eq 0 -or $raw -eq 9223372036854775807) { return (Get-UiText "Value.Never") }
        return (Convert-ADFileTimeToReadableText -Value $raw)
    }
    catch { return [string]$Value }
}

function Convert-BooleanText {
    param([bool]$Value)
    if ($Value) { return "True" }
    return "False"
}

function Get-LockedOutTextFromAdValues {
    param(
        $ComputedUac,
        $LockoutTime
    )

    try {
        if ($null -ne $ComputedUac -and -not (Is-Blank $ComputedUac)) {
            $computed = [int]$ComputedUac
            return (Convert-BooleanText -Value (($computed -band 0x00000010) -ne 0))
        }
    }
    catch { }

    # Fallback used only when the domain controller does not return
    # msDS-User-Account-Control-Computed. A non-zero lockoutTime does not always
    # indicate a current lockout after automatic unlock, but is better than no data.
    try {
        if ($null -ne $LockoutTime -and -not (Is-Blank $LockoutTime)) {
            return (Convert-BooleanText -Value ([Int64]$LockoutTime -gt 0))
        }
    }
    catch { }

    return ""
}

function New-AccountPropertyRow {
    param(
        [string]$Attribute,
        [string]$Value,
        [int]$Count = 1
    )

    return [PSCustomObject]@{
        Attribute = $Attribute
        Value     = $Value
        Count     = $Count
    }
}

function Convert-AdByteArrayValueToText {
    param(
        [string]$Name,
        [byte[]]$Bytes
    )

    if ($null -eq $Bytes) { return "" }

    try {
        if ($Name -ieq "objectGuid") {
            $guid = New-Object System.Guid -ArgumentList (,$Bytes)
            return $guid.ToString()
        }
    }
    catch { }

    try {
        if (($Name -ieq "objectSid") -or ($Name -ieq "sIDHistory")) {
            $sid = New-Object System.Security.Principal.SecurityIdentifier -ArgumentList @($Bytes, 0)
            return $sid.Value
        }
    }
    catch { }

    try {
        return "0x" + ([System.BitConverter]::ToString($Bytes).Replace("-", ""))
    }
    catch {
        return "<byte[]>"
    }
}

function Convert-AdPropertySingleValueToText {
    param(
        [string]$Name,
        $Value
    )

    if ($null -eq $Value) { return "" }

    try {
        if ($Value -is [byte[]]) {
            return Convert-AdByteArrayValueToText -Name $Name -Bytes ([byte[]]$Value)
        }
    }
    catch { }

    try {
        $fileTimeNames = @("pwdLastSet", "lastLogon", "lastLogonTimestamp", "lockoutTime", "badPasswordTime", "msDS-UserPasswordExpiryTimeComputed")
        if ($fileTimeNames -contains $Name) {
            $txt = Convert-ADFileTimeToText -Value $Value
            if (-not (Is-Blank $txt)) { return $txt }
            return [string]$Value
        }

        if ($Name -ieq "accountExpires") {
            $raw = [Int64]$Value
            if ($raw -eq 0 -or $raw -eq 9223372036854775807) {
                $neverText = Get-UiText "Value.Never"
                return "$neverText ($raw)"
            }
            $txt = Convert-ADFileTimeToText -Value $Value
            if (-not (Is-Blank $txt)) { return $txt }
            return [string]$Value
        }

        if ($Name -ieq "userAccountControl") {
            return Convert-UserAccountControlToFlagsText -Value $Value
        }

        if ($Name -ieq "msDS-User-Account-Control-Computed") {
            return Convert-ComputedUserAccountControlToFlagsText -Value $Value
        }
    }
    catch { }

    return [string]$Value
}

function Convert-AdPropertyValueToText {
    param(
        [string]$Name,
        $Value
    )

    if ($null -eq $Value) { return "" }

    try {
        if ($Value -is [byte[]]) {
            return Convert-AdByteArrayValueToText -Name $Name -Bytes ([byte[]]$Value)
        }
    }
    catch { }

    $values = @()
    try {
        if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
            foreach ($v in $Value) { $values += ,$v }
        }
        else {
            $values += ,$Value
        }
    }
    catch {
        $values += ,$Value
    }

    $texts = @()
    foreach ($v in $values) {
        $texts += (Convert-AdPropertySingleValueToText -Name $Name -Value $v)
    }

    return ($texts -join "; ")
}

function Get-AdUserAllPropertiesNoRsat {
    param(
        [string]$DomainOrDc,
        [string]$Login
    )

    $ldapBasePath = Get-LdapBasePath -DomainOrDc $DomainOrDc
    $root = $null
    $searcher = $null
    $result = $null

    try {
        $root = New-Object System.DirectoryServices.DirectoryEntry($ldapBasePath)
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($root)
        $searcher.SearchScope = [System.DirectoryServices.SearchScope]::Subtree
        $searcher.PageSize = 1000

        $loginToSearch = $Login.Trim()
        if ($loginToSearch -match "^[^\\]+\\(.+)$") {
            $loginToSearch = $Matches[1]
        }

        $escaped = Escape-LdapFilterValue -Value $loginToSearch
        if ($loginToSearch -match "@") {
            $searcher.Filter = "(&(objectCategory=person)(objectClass=user)(|(userPrincipalName=$escaped)(sAMAccountName=$escaped)))"
        }
        else {
            $searcher.Filter = "(&(objectCategory=person)(objectClass=user)(sAMAccountName=$escaped))"
        }

        # "*" retrieves regular LDAP attributes. The attributes below are added
        # explicitly to provide values similar to Get-ADUser -Properties *.
        foreach ($p in @(
            "*",
            "pwdLastSet",
            "lockoutTime",
            "msDS-User-Account-Control-Computed",
            "lastLogonTimestamp",
            "lastLogon",
            "accountExpires",
            "userAccountControl",
            "badPwdCount",
            "badPasswordTime"
        )) {
            try { [void]$searcher.PropertiesToLoad.Add($p) } catch { }
        }

        $result = $searcher.FindOne()
        if ($null -eq $result) {
            throw (Get-UiText "Error.AccountNotFound" @($DomainOrDc, $Login))
        }

        $props = $result.Properties
        $rows = @()

        foreach ($name in @($props.PropertyNames | Sort-Object)) {
            $values = $props[$name]
            $count = 0
            try { $count = $values.Count } catch { $count = 1 }
            $text = Convert-AdPropertyValueToText -Name $name -Value $values

            $rows += [PSCustomObject]@{
                Attribute = [string]$name
                Value     = [string]$text
                Count     = [int]$count
            }
        }

        # Computed/helper values corresponding to fields conveniently exposed by Get-ADUser.
        $computedRows = @()

        $uac = Get-SearchPropertyValue -Properties $props -Name "userAccountControl"
        $computedUac = Get-SearchPropertyValue -Properties $props -Name "msDS-User-Account-Control-Computed"
        $pwd = Get-SearchPropertyValue -Properties $props -Name "pwdLastSet"
        $lockoutTime = Get-SearchPropertyValue -Properties $props -Name "lockoutTime"
        $lastLogonTimestamp = Get-SearchPropertyValue -Properties $props -Name "lastLogonTimestamp"
        $accountExpires = Get-SearchPropertyValue -Properties $props -Name "accountExpires"

        if (-not (Is-Blank $uac)) {
            $uacInt = [int]$uac
            $computedRows += (New-AccountPropertyRow -Attribute "Enabled" -Value (Convert-UserAccountControlToEnabled -Value $uac))
            $computedRows += (New-AccountPropertyRow -Attribute "PasswordNeverExpires" -Value (Convert-BooleanText -Value (($uacInt -band 0x00010000) -ne 0)))
            $computedRows += (New-AccountPropertyRow -Attribute "PasswordNotRequired" -Value (Convert-BooleanText -Value (($uacInt -band 0x00000020) -ne 0)))
            $computedRows += (New-AccountPropertyRow -Attribute "SmartcardLogonRequired" -Value (Convert-BooleanText -Value (($uacInt -band 0x00040000) -ne 0)))
            $computedRows += (New-AccountPropertyRow -Attribute "TrustedForDelegation" -Value (Convert-BooleanText -Value (($uacInt -band 0x00080000) -ne 0)))
            $computedRows += (New-AccountPropertyRow -Attribute "userAccountControlFlags" -Value (Convert-UserAccountControlToFlagsText -Value $uac))
        }

        $lockedOut = Get-LockedOutTextFromAdValues -ComputedUac $computedUac -LockoutTime $lockoutTime
        if (-not (Is-Blank $lockedOut)) {
            $computedRows += (New-AccountPropertyRow -Attribute "LockedOut" -Value $lockedOut)
        }

        if (-not (Is-Blank $computedUac)) {
            $computedInt = [int]$computedUac
            $computedRows += (New-AccountPropertyRow -Attribute "PasswordExpired" -Value (Convert-BooleanText -Value (($computedInt -band 0x00800000) -ne 0)))
            $computedRows += (New-AccountPropertyRow -Attribute "msDS-User-Account-Control-ComputedFlags" -Value (Convert-ComputedUserAccountControlToFlagsText -Value $computedUac))
        }

        if (-not (Is-Blank $pwd)) {
            $computedRows += (New-AccountPropertyRow -Attribute "PasswordLastSet" -Value (Convert-ADFileTimeToReadableText -Value $pwd -ZeroText "") )
        }

        if (-not (Is-Blank $lastLogonTimestamp)) {
            $computedRows += (New-AccountPropertyRow -Attribute "LastLogonDate" -Value (Convert-ADFileTimeToReadableText -Value $lastLogonTimestamp))
        }

        if (-not (Is-Blank $accountExpires)) {
            $computedRows += (New-AccountPropertyRow -Attribute "AccountExpirationDate" -Value (Convert-ADAccountExpiresToText -Value $accountExpires))
        }

        if ($computedRows.Count -gt 0) {
            $rows = @($computedRows) + $rows
        }

        return @($rows)
    }
    finally {
        if ($null -ne $searcher) { $searcher.Dispose() }
        if ($null -ne $root) { $root.Dispose() }
    }
}

function Get-DirectoryEntryPropertyValue {
    param(
        [System.DirectoryServices.DirectoryEntry]$Entry,
        [string]$Name
    )

    try {
        if ($null -ne $Entry -and -not (Is-Blank $Name) -and $Entry.Properties.Contains($Name) -and $Entry.Properties[$Name].Count -gt 0) {
            return $Entry.Properties[$Name].Value
        }
    }
    catch { }

    return ""
}

function Convert-GroupTypeToKindText {
    param($Value)

    try {
        if ($null -eq $Value -or (Is-Blank $Value)) { return "" }
        $groupType = [Int64]$Value
        if (($groupType -band 2147483648) -ne 0) { return "Security" }
        return "Distribution"
    }
    catch { return "" }
}

function Convert-GroupTypeToScopeText {
    param($Value)

    try {
        if ($null -eq $Value -or (Is-Blank $Value)) { return "" }
        $groupType = [Int64]$Value
        if (($groupType -band 0x00000008) -ne 0) { return "Universal" }
        if (($groupType -band 0x00000004) -ne 0) { return "Domain local" }
        if (($groupType -band 0x00000002) -ne 0) { return "Global" }
        if (($groupType -band 0x00000001) -ne 0) { return "Builtin local" }
        return ""
    }
    catch { return "" }
}

function New-AccountGroupRowFromSearchProperties {
    param(
        $Properties,
        [string]$Source
    )

    $groupType = Get-SearchPropertyValue -Properties $Properties -Name "groupType"
    return [PSCustomObject]@{
        Name              = [string](Get-SearchPropertyValue -Properties $Properties -Name "name")
        SamAccountName    = [string](Get-SearchPropertyValue -Properties $Properties -Name "sAMAccountName")
        DisplayName       = [string](Get-SearchPropertyValue -Properties $Properties -Name "displayName")
        Type              = Convert-GroupTypeToKindText -Value $groupType
        Scope             = Convert-GroupTypeToScopeText -Value $groupType
        Source            = [string]$Source
        Description       = [string](Get-SearchPropertyValue -Properties $Properties -Name "description")
        DistinguishedName = [string](Get-SearchPropertyValue -Properties $Properties -Name "distinguishedName")
    }
}

function Convert-SidStringToLdapFilterValue {
    param([string]$Sid)

    if (Is-Blank $Sid) { return "" }

    $securityIdentifier = New-Object System.Security.Principal.SecurityIdentifier -ArgumentList $Sid
    $bytes = New-Object byte[] ($securityIdentifier.BinaryLength)
    $securityIdentifier.GetBinaryForm($bytes, 0)

    $parts = @()
    foreach ($b in $bytes) {
        $parts += ("\{0:X2}" -f [int]$b)
    }
    return ($parts -join "")
}

function Find-AdGroupByDistinguishedNameNoRsat {
    param(
        [string]$DomainOrDc,
        [string]$DistinguishedName,
        [string]$Source = "memberOf"
    )

    if (Is-Blank $DistinguishedName) { return $null }

    $ldapBasePath = Get-LdapBasePath -DomainOrDc $DomainOrDc
    $root = $null
    $searcher = $null
    $result = $null

    try {
        $root = New-Object System.DirectoryServices.DirectoryEntry($ldapBasePath)
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($root)
        $searcher.SearchScope = [System.DirectoryServices.SearchScope]::Subtree
        $searcher.PageSize = 1000
        $escapedDn = Escape-LdapFilterValue -Value $DistinguishedName
        $searcher.Filter = "(&(objectClass=group)(distinguishedName=$escapedDn))"

        foreach ($p in @("sAMAccountName", "name", "displayName", "groupType", "description", "distinguishedName")) {
            [void]$searcher.PropertiesToLoad.Add($p)
        }

        $result = $searcher.FindOne()
        if ($null -eq $result) { return $null }
        return (New-AccountGroupRowFromSearchProperties -Properties $result.Properties -Source $Source)
    }
    finally {
        if ($null -ne $searcher) { $searcher.Dispose() }
        if ($null -ne $root) { $root.Dispose() }
    }
}

function Find-AdGroupBySidNoRsat {
    param(
        [string]$DomainOrDc,
        [string]$Sid,
        [string]$Source = "primaryGroupID"
    )

    if (Is-Blank $Sid) { return $null }

    $ldapBasePath = Get-LdapBasePath -DomainOrDc $DomainOrDc
    $root = $null
    $searcher = $null
    $result = $null

    try {
        $sidFilter = Convert-SidStringToLdapFilterValue -Sid $Sid
        if (Is-Blank $sidFilter) { return $null }

        $root = New-Object System.DirectoryServices.DirectoryEntry($ldapBasePath)
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($root)
        $searcher.SearchScope = [System.DirectoryServices.SearchScope]::Subtree
        $searcher.PageSize = 1000
        $searcher.Filter = "(&(objectClass=group)(objectSid=$sidFilter))"

        foreach ($p in @("sAMAccountName", "name", "displayName", "groupType", "description", "distinguishedName")) {
            [void]$searcher.PropertiesToLoad.Add($p)
        }

        $result = $searcher.FindOne()
        if ($null -eq $result) { return $null }
        return (New-AccountGroupRowFromSearchProperties -Properties $result.Properties -Source $Source)
    }
    finally {
        if ($null -ne $searcher) { $searcher.Dispose() }
        if ($null -ne $root) { $root.Dispose() }
    }
}

function Get-AdAccountGroupsNoRsat {
    param(
        [string]$DomainOrDc,
        [string]$Login,
        $ProgressWindow = $null
    )

    Set-BusyProgressWindow -ProgressWindow $ProgressWindow -Message (Get-UiText "Progress.FindAccount") -Detail "$DomainOrDc\$Login" -Marquee $true
    $target = Find-AdUserBasic -DomainOrDc $DomainOrDc -Login $Login
    if ($null -eq $target -or (Is-Blank $target.DistinguishedName)) {
        throw (Get-UiText "Error.AccountNotFound" @($DomainOrDc, $Login))
    }

    $entry = $null
    $rows = @()

    try {
        $entry = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$DomainOrDc/$($target.DistinguishedName)")
        Set-BusyProgressWindow -ProgressWindow $ProgressWindow -Message (Get-UiText "Progress.ReadAccount") -Detail $target.DistinguishedName -Marquee $true
        try { $entry.RefreshCache(@("memberOf", "primaryGroupID", "objectSid")) } catch { }

        $memberOf = @()
        try {
            foreach ($dn in $entry.Properties["memberOf"]) {
                if (-not (Is-Blank $dn)) { $memberOf += [string]$dn }
            }
        }
        catch { }

        $memberOfUnique = @($memberOf | Sort-Object -Unique)
        $groupIndex = 0
        $groupTotal = $memberOfUnique.Count
        if ($groupTotal -gt 0) {
            Set-BusyProgressWindow -ProgressWindow $ProgressWindow -Message (Get-UiText "Progress.ReadMemberOf") -Detail "0 / $groupTotal" -Value 0 -Maximum $groupTotal
        }

        foreach ($groupDn in $memberOfUnique) {
            $groupIndex++
            Set-BusyProgressWindow -ProgressWindow $ProgressWindow -Message (Get-UiText "Progress.ReadMemberOf") -Detail "$groupIndex / $groupTotal" -Value $groupIndex -Maximum $groupTotal
            $groupRow = Find-AdGroupByDistinguishedNameNoRsat -DomainOrDc $DomainOrDc -DistinguishedName $groupDn -Source "memberOf"
            if ($null -ne $groupRow) { $rows += $groupRow }
        }

        # primaryGroupID usually represents a group such as Domain Users and is absent
        # from memberOf, so it is added separately to provide a more complete list.
        try {
            $primaryGroupId = Get-DirectoryEntryPropertyValue -Entry $entry -Name "primaryGroupID"
            $objectSid = Get-DirectoryEntryPropertyValue -Entry $entry -Name "objectSid"

            if ($null -ne $primaryGroupId -and -not (Is-Blank $primaryGroupId) -and $null -ne $objectSid) {
                $sidObj = New-Object System.Security.Principal.SecurityIdentifier -ArgumentList @([byte[]]$objectSid, 0)
                $userSid = $sidObj.Value
                $lastDash = $userSid.LastIndexOf("-")
                if ($lastDash -gt 0) {
                    $domainSid = $userSid.Substring(0, $lastDash)
                    $primaryGroupSid = "$domainSid-$([int]$primaryGroupId)"
                    Set-BusyProgressWindow -ProgressWindow $ProgressWindow -Message (Get-UiText "Progress.CheckPrimaryGroup") -Detail $primaryGroupSid -Marquee $true
                    $primaryRow = Find-AdGroupBySidNoRsat -DomainOrDc $DomainOrDc -Sid $primaryGroupSid -Source "primaryGroupID"
                    if ($null -ne $primaryRow) { $rows += $primaryRow }
                }
            }
        }
        catch { }

        $unique = @{}
        $deduped = @()
        foreach ($row in $rows) {
            if ($null -eq $row) { continue }
            $key = [string]$row.DistinguishedName
            if (Is-Blank $key) { $key = [string]$row.SamAccountName }
            if (Is-Blank $key) { $key = [string]$row.Name }
            if (Is-Blank $key) { continue }
            $lowerKey = $key.ToLowerInvariant()
            if (-not $unique.ContainsKey($lowerKey)) {
                $unique[$lowerKey] = $true
                $deduped += $row
            }
        }

        Set-BusyProgressWindow -ProgressWindow $ProgressWindow -Message (Get-UiText "Progress.OrganizeResult") -Detail (Get-UiText "Progress.DeduplicateGroups") -Marquee $true
        return @($deduped | Sort-Object -Property @("Name", "SamAccountName"))
    }
    finally {
        if ($null -ne $entry) { $entry.Dispose() }
    }
}



function Get-SearchPropertyValues {
    param(
        $Properties,
        [string]$Name
    )

    $values = @()
    if ($null -eq $Properties -or (Is-Blank $Name)) { return @() }

    try {
        $matchingKey = $null
        foreach ($propertyName in $Properties.PropertyNames) {
            if ($propertyName -ieq $Name) {
                $matchingKey = $propertyName
                break
            }
        }

        if ($null -ne $matchingKey -and $Properties[$matchingKey].Count -gt 0) {
            foreach ($v in $Properties[$matchingKey]) {
                if ($null -ne $v) { $values += $v }
            }
        }
    }
    catch { }

    return @($values)
}

function Get-AdObjectTypeFromProperties {
    param($Properties)

    try {
        $classes = @(Get-SearchPropertyValues -Properties $Properties -Name "objectClass")
        if ($classes.Count -gt 0) {
            return [string]$classes[$classes.Count - 1]
        }
    }
    catch { }

    return [string](Get-SearchPropertyValue -Properties $Properties -Name "objectClass")
}

function Find-AdGroupBasicNoRsat {
    param(
        [string]$DomainOrDc,
        [string]$GroupIdentity
    )

    if (Is-Blank $GroupIdentity) { return $null }

    $ldapBasePath = Get-LdapBasePath -DomainOrDc $DomainOrDc
    $root = $null
    $searcher = $null
    $result = $null

    try {
        $root = New-Object System.DirectoryServices.DirectoryEntry($ldapBasePath)
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($root)
        $searcher.SearchScope = [System.DirectoryServices.SearchScope]::Subtree
        $searcher.PageSize = 1000

        $escaped = Escape-LdapFilterValue -Value $GroupIdentity
        if ($GroupIdentity -match "^CN=.*?,.*DC=.*") {
            $searcher.Filter = "(&(objectClass=group)(distinguishedName=$escaped))"
        }
        else {
            $searcher.Filter = "(&(objectClass=group)(|(sAMAccountName=$escaped)(name=$escaped)(cn=$escaped)))"
        }

        foreach ($p in @("sAMAccountName", "name", "displayName", "description", "distinguishedName", "groupType", "objectSid")) {
            [void]$searcher.PropertiesToLoad.Add($p)
        }

        $result = $searcher.FindOne()
        if ($null -eq $result) { return $null }

        return (New-AccountGroupRowFromSearchProperties -Properties $result.Properties -Source "group")
    }
    finally {
        if ($null -ne $searcher) { $searcher.Dispose() }
        if ($null -ne $root) { $root.Dispose() }
    }
}

function Get-AdGroupMemberDistinguishedNamesNoRsat {
    param(
        [string]$DomainOrDc,
        [string]$GroupDistinguishedName,
        $ProgressWindow = $null
    )

    $memberDns = @()
    if (Is-Blank $GroupDistinguishedName) { return @() }

    $ldapBasePath = Get-LdapBasePath -DomainOrDc $DomainOrDc
    $root = $null
    $searcher = $null

    try {
        $root = New-Object System.DirectoryServices.DirectoryEntry($ldapBasePath)
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($root)
        $searcher.SearchScope = [System.DirectoryServices.SearchScope]::Subtree
        $searcher.PageSize = 1000
        $escapedDn = Escape-LdapFilterValue -Value $GroupDistinguishedName
        $searcher.Filter = "(&(objectClass=group)(distinguishedName=$escapedDn))"

        $rangeStart = 0
        $rangeStep = 1500
        $done = $false

        while (-not $done) {
            try { $searcher.PropertiesToLoad.Clear() } catch { }
            $rangeEnd = $rangeStart + $rangeStep - 1
            $rangeProp = "member;range=$rangeStart-$rangeEnd"
            [void]$searcher.PropertiesToLoad.Add($rangeProp)

            Set-BusyProgressWindow -ProgressWindow $ProgressWindow -Message (Get-UiText "Progress.ReadMemberList") -Detail (Get-UiText "Progress.Range" @($rangeStart, $rangeEnd)) -Marquee $true
            $result = $searcher.FindOne()
            if ($null -eq $result) { break }

            $foundRangeProperty = $null
            foreach ($propertyName in $result.Properties.PropertyNames) {
                if ($propertyName -like "member;range=*") {
                    $foundRangeProperty = [string]$propertyName
                    break
                }
            }

            if (-not (Is-Blank $foundRangeProperty)) {
                foreach ($dn in $result.Properties[$foundRangeProperty]) {
                    if (-not (Is-Blank $dn)) { $memberDns += [string]$dn }
                }

                if ($foundRangeProperty.EndsWith("-*")) {
                    $done = $true
                }
                else {
                    $rangeStart += $rangeStep
                }
            }
            else {
                # Fallback for small groups or other domain controller behavior.
                try { $searcher.PropertiesToLoad.Clear() } catch { }
                [void]$searcher.PropertiesToLoad.Add("member")
                $result = $searcher.FindOne()
                if ($null -ne $result -and $result.Properties.Contains("member")) {
                    foreach ($dn in $result.Properties["member"]) {
                        if (-not (Is-Blank $dn)) { $memberDns += [string]$dn }
                    }
                }
                $done = $true
            }
        }
    }
    finally {
        if ($null -ne $searcher) { $searcher.Dispose() }
        if ($null -ne $root) { $root.Dispose() }
    }

    return @($memberDns | Sort-Object -Unique)
}

function New-DomainGroupMemberRowFromSearchProperties {
    param($Properties)

    $uac = Get-SearchPropertyValue -Properties $Properties -Name "userAccountControl"
    $objectType = Get-AdObjectTypeFromProperties -Properties $Properties

    return [PSCustomObject]@{
        Name              = [string](Get-SearchPropertyValue -Properties $Properties -Name "name")
        SamAccountName    = [string](Get-SearchPropertyValue -Properties $Properties -Name "sAMAccountName")
        DisplayName       = [string](Get-SearchPropertyValue -Properties $Properties -Name "displayName")
        ObjectType        = [string]$objectType
        Enabled           = if ($objectType -in @("user", "computer")) { Convert-UserAccountControlToEnabled -Value $uac } else { "" }
        UserPrincipalName = [string](Get-SearchPropertyValue -Properties $Properties -Name "userPrincipalName")
        Description       = [string](Get-SearchPropertyValue -Properties $Properties -Name "description")
        DistinguishedName = [string](Get-SearchPropertyValue -Properties $Properties -Name "distinguishedName")
    }
}

function Find-AdObjectByDistinguishedNameNoRsat {
    param(
        [string]$DomainOrDc,
        [string]$DistinguishedName
    )

    if (Is-Blank $DistinguishedName) { return $null }

    $ldapBasePath = Get-LdapBasePath -DomainOrDc $DomainOrDc
    $root = $null
    $searcher = $null
    $result = $null

    try {
        $root = New-Object System.DirectoryServices.DirectoryEntry($ldapBasePath)
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($root)
        $searcher.SearchScope = [System.DirectoryServices.SearchScope]::Subtree
        $searcher.PageSize = 1000
        $escapedDn = Escape-LdapFilterValue -Value $DistinguishedName
        $searcher.Filter = "(distinguishedName=$escapedDn)"

        foreach ($p in @("sAMAccountName", "name", "displayName", "userPrincipalName", "distinguishedName", "description", "userAccountControl", "objectClass", "mail")) {
            [void]$searcher.PropertiesToLoad.Add($p)
        }

        $result = $searcher.FindOne()
        if ($null -eq $result) {
            return [PSCustomObject]@{
                Name              = ""
                SamAccountName    = ""
                DisplayName       = ""
                ObjectType        = "nieznany"
                Enabled           = ""
                UserPrincipalName = ""
                Description       = Get-UiText "Value.UnknownObject"
                DistinguishedName = [string]$DistinguishedName
            }
        }

        return (New-DomainGroupMemberRowFromSearchProperties -Properties $result.Properties)
    }
    finally {
        if ($null -ne $searcher) { $searcher.Dispose() }
        if ($null -ne $root) { $root.Dispose() }
    }
}

function Get-AdDomainGroupMembersNoRsat {
    param(
        [string]$DomainOrDc,
        [string]$GroupIdentity,
        $ProgressWindow = $null
    )

    Set-BusyProgressWindow -ProgressWindow $ProgressWindow -Message (Get-UiText "Progress.FindGroup") -Detail "$DomainOrDc\$GroupIdentity" -Marquee $true
    $group = Find-AdGroupBasicNoRsat -DomainOrDc $DomainOrDc -GroupIdentity $GroupIdentity
    if ($null -eq $group -or (Is-Blank $group.DistinguishedName)) {
        throw (Get-UiText "Error.GroupNotFound" @($DomainOrDc, $GroupIdentity))
    }

    Set-BusyProgressWindow -ProgressWindow $ProgressWindow -Message (Get-UiText "Progress.GetMemberList") -Detail $group.DistinguishedName -Marquee $true
    $memberDns = @(Get-AdGroupMemberDistinguishedNamesNoRsat -DomainOrDc $DomainOrDc -GroupDistinguishedName $group.DistinguishedName -ProgressWindow $ProgressWindow)

    $rows = @()
    $total = $memberDns.Count

    if ($total -gt 0) {
        Set-BusyProgressWindow -ProgressWindow $ProgressWindow -Message (Get-UiText "Progress.GetMemberObjects") -Detail "0 / $total" -Value 0 -Maximum $total
    }

    $index = 0
    foreach ($dn in $memberDns) {
        $index++
        Set-BusyProgressWindow -ProgressWindow $ProgressWindow -Message (Get-UiText "Progress.GetMemberObjects") -Detail "$index / $total" -Value $index -Maximum $total
        $row = Find-AdObjectByDistinguishedNameNoRsat -DomainOrDc $DomainOrDc -DistinguishedName $dn
        if ($null -ne $row) { $rows += $row }
    }

    Set-BusyProgressWindow -ProgressWindow $ProgressWindow -Message (Get-UiText "Progress.OrganizeResult") -Detail (Get-UiText "Progress.SortGroupMembers") -Marquee $true
    return @($rows | Sort-Object -Property @("ObjectType", "SamAccountName", "Name", "DistinguishedName"))
}

function Get-ManagedAccounts {
    param(
        [string]$DomainOrDc,
        [string]$ManagerLogin
    )

    $manager = Find-AdUserBasic -DomainOrDc $DomainOrDc -Login $ManagerLogin
    if ($null -eq $manager -or (Is-Blank $manager.DistinguishedName)) {
        throw (Get-UiText "Error.ManagerNotFound" @($DomainOrDc, $ManagerLogin))
    }

    $escapedManagerDn = Escape-LdapFilterValue -Value $manager.DistinguishedName
    $ldapBasePath = Get-LdapBasePath -DomainOrDc $DomainOrDc

    $root = $null
    $searcher = $null
    $results = $null

    try {
        $root = New-Object System.DirectoryServices.DirectoryEntry($ldapBasePath)
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($root)
        $searcher.PageSize = 1000
        $searcher.SearchScope = [System.DirectoryServices.SearchScope]::Subtree
        $searcher.Filter = "(&(objectCategory=person)(objectClass=user)(manager=$escapedManagerDn))"

        foreach ($p in @("sAMAccountName", "name", "displayName", "userPrincipalName", "distinguishedName", "description", "userAccountControl", "pwdLastSet")) {
            [void]$searcher.PropertiesToLoad.Add($p)
        }

        $results = $searcher.FindAll()
        $rows = @()

        foreach ($result in $results) {
            $props = $result.Properties
            $uac = Get-SearchPropertyValue -Properties $props -Name "userAccountControl"
            $pwd = Get-SearchPropertyValue -Properties $props -Name "pwdLastSet"

            $rows += [PSCustomObject]@{
                SamAccountName    = [string](Get-SearchPropertyValue -Properties $props -Name "sAMAccountName")
                Name              = [string](Get-SearchPropertyValue -Properties $props -Name "name")
                DisplayName       = [string](Get-SearchPropertyValue -Properties $props -Name "displayName")
                Enabled           = Convert-UserAccountControlToEnabled -Value $uac
                UserPrincipalName = [string](Get-SearchPropertyValue -Properties $props -Name "userPrincipalName")
                Description       = [string](Get-SearchPropertyValue -Properties $props -Name "description")
                PasswordLastSet   = Convert-ADFileTimeToText -Value $pwd
                DistinguishedName = [string](Get-SearchPropertyValue -Properties $props -Name "distinguishedName")
            }
        }

        return @($rows | Sort-Object SamAccountName)
    }
    finally {
        if ($null -ne $results) { $results.Dispose() }
        if ($null -ne $searcher) { $searcher.Dispose() }
        if ($null -ne $root) { $root.Dispose() }
    }
}


function Get-ManagedGroups {
    param(
        [string]$DomainOrDc,
        [string]$ManagerLogin,
        $ProgressWindow = $null
    )

    Set-BusyProgressWindow -ProgressWindow $ProgressWindow -Message (Get-UiText "Progress.FindManager") -Detail "$DomainOrDc\$ManagerLogin" -Marquee $true
    $manager = Find-AdUserBasic -DomainOrDc $DomainOrDc -Login $ManagerLogin
    if ($null -eq $manager -or (Is-Blank $manager.DistinguishedName)) {
        throw (Get-UiText "Error.ManagerNotFound" @($DomainOrDc, $ManagerLogin))
    }

    $escapedManagerDn = Escape-LdapFilterValue -Value $manager.DistinguishedName
    $ldapBasePath = Get-LdapBasePath -DomainOrDc $DomainOrDc

    $root = $null
    $searcher = $null
    $results = $null

    try {
        Set-BusyProgressWindow -ProgressWindow $ProgressWindow -Message (Get-UiText "Progress.FindManagedGroups") -Detail $manager.DistinguishedName -Marquee $true
        $root = New-Object System.DirectoryServices.DirectoryEntry($ldapBasePath)
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($root)
        $searcher.PageSize = 1000
        $searcher.SearchScope = [System.DirectoryServices.SearchScope]::Subtree
        $searcher.Filter = "(&(objectClass=group)(managedBy=$escapedManagerDn))"

        foreach ($p in @("sAMAccountName", "name", "displayName", "groupType", "description", "distinguishedName", "managedBy")) {
            [void]$searcher.PropertiesToLoad.Add($p)
        }

        $results = $searcher.FindAll()
        $rows = @()
        $total = $results.Count
        $index = 0

        if ($total -gt 0) {
            Set-BusyProgressWindow -ProgressWindow $ProgressWindow -Message (Get-UiText "Progress.OrganizeManagedGroups") -Detail "0 / $total" -Value 0 -Maximum $total
        }

        foreach ($result in $results) {
            $index++
            Set-BusyProgressWindow -ProgressWindow $ProgressWindow -Message (Get-UiText "Progress.OrganizeManagedGroups") -Detail "$index / $total" -Value $index -Maximum $total
            $rows += (New-AccountGroupRowFromSearchProperties -Properties $result.Properties -Source "managedBy")
        }

        return @($rows | Sort-Object -Property @("Name", "SamAccountName", "DistinguishedName"))
    }
    finally {
        if ($null -ne $results) { $results.Dispose() }
        if ($null -ne $searcher) { $searcher.Dispose() }
        if ($null -ne $root) { $root.Dispose() }
    }
}


# ==================================================
# CSV / XLSX export without additional modules
# ==================================================

function Convert-ManagedRowsToExportRows {
    param([object[]]$Rows)

    $exportRows = @()
    if ($null -eq $Rows) { return $exportRows }

    foreach ($row in $Rows) {
        if ($null -eq $row) { continue }
        $exportRow = [ordered]@{}
        $exportRow[(Get-UiText "Column.Login")] = [string]$row.SamAccountName
        $exportRow[(Get-UiText "Column.Name")] = [string]$row.Name
        $exportRow[(Get-UiText "Column.DisplayName")] = [string]$row.DisplayName
        $exportRow[(Get-UiText "Column.Enabled")] = [string]$row.Enabled
        $exportRow["UPN"] = [string]$row.UserPrincipalName
        $exportRow[(Get-UiText "Column.Description")] = [string]$row.Description
        $exportRow[(Get-UiText "Column.PasswordLastSet")] = [string]$row.PasswordLastSet
        $exportRows += [PSCustomObject]$exportRow
    }
    return $exportRows
}

function Get-SafeFileNamePart {
    param([string]$Text)

    if (Is-Blank $Text) { return (Get-UiText "Export.NoDataPart") }
    $safe = [regex]::Replace($Text.Trim(), '[\\/:*?"<>|]+', '_')
    $safe = [regex]::Replace($safe, '\s+', '_')
    $safe = $safe.Trim('_')
    if (Is-Blank $safe) { return (Get-UiText "Export.NoDataPart") }
    return $safe
}

function Export-ManagedAccountsToCsv {
    param([object[]]$Rows, [string]$Path)

    $exportRows = @(Convert-ManagedRowsToExportRows -Rows $Rows)
    if ($exportRows.Count -eq 0) { throw (Get-UiText "Error.ExportNoAccounts") }
    $exportRows | Export-Csv -Path $Path -NoTypeInformation -Delimiter ";" -Encoding UTF8 -Force
}

function Convert-ToExcelColumnName {
    param([int]$ColumnNumber)

    if ($ColumnNumber -lt 1) { throw (Get-UiText "Error.ExcelColumn" @($ColumnNumber)) }
    $name = ""
    $n = $ColumnNumber
    while ($n -gt 0) {
        $mod = ($n - 1) % 26
        $name = ([char](65 + $mod)) + $name
        $n = [math]::Floor(($n - $mod) / 26)
    }
    return $name
}

function Convert-ToXmlText {
    param([object]$Value)

    if ($null -eq $Value) { return "" }
    $text = [string]$Value
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $text.ToCharArray()) {
        $code = [int][char]$ch
        if (($code -eq 9) -or ($code -eq 10) -or ($code -eq 13) -or ($code -ge 32)) {
            [void]$sb.Append($ch)
        }
    }
    return [System.Security.SecurityElement]::Escape($sb.ToString())
}

function New-XlsxInlineStringCellXml {
    param([string]$CellRef, [object]$Value, [int]$StyleIndex = 0)

    $xmlText = Convert-ToXmlText -Value $Value
    $styleText = ""
    if ($StyleIndex -gt 0) { $styleText = " s=`"$StyleIndex`"" }
    $spaceText = ""
    $plainText = [string]$Value
    if ($plainText -match '^\s|\s$') { $spaceText = ' xml:space="preserve"' }
    return "<c r=`"$CellRef`" t=`"inlineStr`"$styleText><is><t$spaceText>$xmlText</t></is></c>"
}

function Write-Utf8NoBomFile {
    param([string]$Path, [string]$Content)
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Export-ManagedAccountsToXlsx {
    param([object[]]$Rows, [string]$Path)

    $exportRows = @(Convert-ManagedRowsToExportRows -Rows $Rows)
    if ($exportRows.Count -eq 0) { throw (Get-UiText "Error.ExportNoAccounts") }

    $headers = @(
        (Get-UiText "Column.Login"),
        (Get-UiText "Column.Name"),
        (Get-UiText "Column.DisplayName"),
        (Get-UiText "Column.Enabled"),
        "UPN",
        (Get-UiText "Column.Description"),
        (Get-UiText "Column.PasswordLastSet")
    )
    $widths = @(18, 24, 28, 12, 34, 42, 22)
    $lastColumnName = Convert-ToExcelColumnName -ColumnNumber $headers.Count
    $lastRow = $exportRows.Count + 1
    $sheetRef = "A1:$lastColumnName$lastRow"
    $tmp = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "ADKombajn_xlsx_" + [guid]::NewGuid().ToString("N"))

    try {
        [void](New-Item -Path $tmp -ItemType Directory -Force)
        foreach ($dir in @("_rels", "docProps", "xl", "xl\_rels", "xl\worksheets")) {
            [void](New-Item -Path (Join-Path $tmp $dir) -ItemType Directory -Force)
        }

        $nowUtc = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        $sheetName = Convert-ToXmlText -Value (Get-UiText "Export.SheetName")

        Write-Utf8NoBomFile -Path (Join-Path $tmp "[Content_Types].xml") -Content @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
  <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>
"@

        Write-Utf8NoBomFile -Path (Join-Path $tmp "_rels\.rels") -Content @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>
"@

        Write-Utf8NoBomFile -Path (Join-Path $tmp "docProps\core.xml") -Content @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <dc:creator>ADKombajn</dc:creator>
  <cp:lastModifiedBy>ADKombajn</cp:lastModifiedBy>
  <dcterms:created xsi:type="dcterms:W3CDTF">$nowUtc</dcterms:created>
  <dcterms:modified xsi:type="dcterms:W3CDTF">$nowUtc</dcterms:modified>
</cp:coreProperties>
"@

        Write-Utf8NoBomFile -Path (Join-Path $tmp "docProps\app.xml") -Content @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
  <Application>ADKombajn</Application>
</Properties>
"@

        Write-Utf8NoBomFile -Path (Join-Path $tmp "xl\workbook.xml") -Content @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets><sheet name="$sheetName" sheetId="1" r:id="rId1"/></sheets>
</workbook>
"@

        Write-Utf8NoBomFile -Path (Join-Path $tmp "xl\_rels\workbook.xml.rels") -Content @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>
"@

        Write-Utf8NoBomFile -Path (Join-Path $tmp "xl\styles.xml") -Content @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font></fonts>
  <fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF1F4E78"/><bgColor indexed="64"/></patternFill></fill></fills>
  <borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left style="thin"><color rgb="FFD9E2F3"/></left><right style="thin"><color rgb="FFD9E2F3"/></right><top style="thin"><color rgb="FFD9E2F3"/></top><bottom style="thin"><color rgb="FFD9E2F3"/></bottom><diagonal/></border></borders>
  <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
  <cellXfs count="3"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf><xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf></cellXfs>
  <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>
"@

        $colsXml = New-Object System.Text.StringBuilder
        [void]$colsXml.AppendLine("  <cols>")
        for ($i = 0; $i -lt $widths.Count; $i++) {
            $colNum = $i + 1
            [void]$colsXml.AppendLine("    <col min=`"$colNum`" max=`"$colNum`" width=`"$($widths[$i])`" customWidth=`"1`"/>")
        }
        [void]$colsXml.AppendLine("  </cols>")

        $sheetData = New-Object System.Text.StringBuilder
        [void]$sheetData.AppendLine("  <sheetData>")
        [void]$sheetData.Append("    <row r=`"1`" ht=`"20`" customHeight=`"1`">")
        for ($i = 0; $i -lt $headers.Count; $i++) {
            $cellRef = (Convert-ToExcelColumnName -ColumnNumber ($i + 1)) + "1"
            [void]$sheetData.Append((New-XlsxInlineStringCellXml -CellRef $cellRef -Value $headers[$i] -StyleIndex 1))
        }
        [void]$sheetData.AppendLine("</row>")

        $rowNumber = 2
        foreach ($exportRow in $exportRows) {
            [void]$sheetData.Append("    <row r=`"$rowNumber`">")
            for ($i = 0; $i -lt $headers.Count; $i++) {
                $header = $headers[$i]
                $cellRef = (Convert-ToExcelColumnName -ColumnNumber ($i + 1)) + $rowNumber
                [void]$sheetData.Append((New-XlsxInlineStringCellXml -CellRef $cellRef -Value $exportRow.$header -StyleIndex 2))
            }
            [void]$sheetData.AppendLine("</row>")
            $rowNumber++
        }
        [void]$sheetData.AppendLine("  </sheetData>")

        Write-Utf8NoBomFile -Path (Join-Path $tmp "xl\worksheets\sheet1.xml") -Content @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <dimension ref="$sheetRef"/>
  <sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/><selection pane="bottomLeft"/></sheetView></sheetViews>
  <sheetFormatPr defaultRowHeight="15"/>
$($colsXml.ToString())$($sheetData.ToString())  <autoFilter ref="$sheetRef"/>
  <pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" header="0.3" footer="0.3"/>
</worksheet>
"@

        if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
        [System.IO.Compression.ZipFile]::CreateFromDirectory($tmp, $Path)
    }
    finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# ==================================================
# Manager account table data
# ==================================================

function Get-ManagedAccountsFilterMode {
    if ($rdoManagedActive.Checked) { return "Active" }
    if ($rdoManagedInactive.Checked) { return "Inactive" }
    return "All"
}

function Get-ManagedAccountsFilterText {
    $mode = Get-ManagedAccountsFilterMode
    switch ($mode) {
        "Active"   { return (Get-UiText "Filter.Active") }
        "Inactive" { return (Get-UiText "Filter.Inactive") }
        default    { return (Get-UiText "Filter.All") }
    }
}

function Filter-ManagedAccountsRows {
    param([object[]]$Rows)

    if ($null -eq $Rows) { return @() }
    $mode = Get-ManagedAccountsFilterMode
    $query = ""
    try { $query = $txtManagedSearch.Text.Trim() } catch { }

    $filtered = @($Rows)
    switch ($mode) {
        "Active"   { $filtered = @($filtered | Where-Object { $_.Enabled -eq "True" }) }
        "Inactive" { $filtered = @($filtered | Where-Object { $_.Enabled -eq "False" }) }
    }

    if (-not (Is-Blank $query)) {
        $q = $query.ToLowerInvariant()
        $filtered = @($filtered | Where-Object {
            ([string]$_.SamAccountName).ToLowerInvariant().Contains($q) -or
            ([string]$_.DisplayName).ToLowerInvariant().Contains($q) -or
            ([string]$_.Name).ToLowerInvariant().Contains($q) -or
            ([string]$_.UserPrincipalName).ToLowerInvariant().Contains($q) -or
            ([string]$_.Description).ToLowerInvariant().Contains($q)
        })
    }

    return @($filtered)
}

function New-TextGridColumn {
    param([string]$Name, [string]$HeaderText, [int]$Width, [bool]$Visible = $true)

    $column = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $column.Name = $Name
    $column.HeaderText = $HeaderText
    $column.Width = $Width
    $column.ReadOnly = $true
    $column.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::Automatic
    $column.Visible = $Visible
    return $column
}

function Set-ManagedAccountsGrid {
    param([object[]]$Rows)

    $gridManaged.SuspendLayout()
    try {
        $gridManaged.Rows.Clear()
        if ($null -ne $Rows) {
            foreach ($row in $Rows) {
                if ($null -eq $row) { continue }
                [void]$gridManaged.Rows.Add(
                    [string]$row.SamAccountName,
                    [string]$row.Name,
                    [string]$row.DisplayName,
                    [string]$row.Enabled,
                    [string]$row.UserPrincipalName,
                    [string]$row.Description,
                    [string]$row.PasswordLastSet,
                    [string]$row.DistinguishedName
                )
            }
        }
        $gridManaged.ClearSelection()
    }
    finally {
        $gridManaged.ResumeLayout()
    }

    $gridManaged.Refresh()
}

function Refresh-ManagedAccountsGrid {
    $filteredRows = @(Filter-ManagedAccountsRows -Rows $script:ManagedRowsAll)
    $totalCount = @($script:ManagedRowsAll).Count
    Set-ManagedAccountsGrid -Rows $filteredRows

    if ((Get-ManagedAccountsFilterMode) -eq "All" -and (Is-Blank $txtManagedSearch.Text)) {
        $lblManagedCount.Text = Get-UiText "ManagerAccounts.Count" @($filteredRows.Count)
    }
    else {
        $lblManagedCount.Text = Get-UiText "ManagerAccounts.CountFiltered" @($filteredRows.Count, $totalCount)
    }
    return $filteredRows.Count
}

function Update-ManagedAccountsFilterView {
    if (-not $script:ManagedRowsLoaded) { return }
    $visibleCount = Refresh-ManagedAccountsGrid
    $totalCount = @($script:ManagedRowsAll).Count
    Set-Status (Get-UiText "Status.Filter" @((Get-ManagedAccountsFilterText), $txtManagedSearch.Text, $visibleCount, $totalCount)) "Info"
}

function Get-CurrentVisibleManagedRows {
    if (-not $script:ManagedRowsLoaded) { return @() }
    return @(Filter-ManagedAccountsRows -Rows $script:ManagedRowsAll)
}

function Export-ManagedAccountsWithDialog {
    param([ValidateSet("CSV", "XLSX")][string]$Format)

    if (-not $script:ManagedRowsLoaded -or (@($script:ManagedRowsAll).Count -eq 0)) {
        Show-InfoBox (Get-UiText "Status.GetManagerAccountsFirst") (Get-UiText "Dialog.NoData")
        return
    }

    $rowsToExport = @(Get-CurrentVisibleManagedRows)
    if ($rowsToExport.Count -eq 0) {
        Show-InfoBox (Get-UiText "Status.FilterHasNoAccounts") (Get-UiText "Dialog.NoData")
        return
    }

    $domainPart = Get-SafeFileNamePart -Text $txtDomain.Text
    $loginPart = Get-SafeFileNamePart -Text $txtLogin.Text
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $filterPart = Get-SafeFileNamePart -Text (Get-ManagedAccountsFilterText)
    $extension = $Format.ToLowerInvariant()
    $fileNameBase = Get-UiText "Export.FileNameBase"
    $defaultName = "${fileNameBase}_${domainPart}_${loginPart}_${filterPart}_${stamp}.${extension}"

    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Title = Get-UiText "Export.SaveTitle"
    $dialog.FileName = $defaultName
    $dialog.OverwritePrompt = $true

    if ($Format -eq "CSV") {
        $dialog.Filter = Get-UiText "Export.CsvFilter"
        $dialog.DefaultExt = "csv"
    }
    else {
        $dialog.Filter = Get-UiText "Export.XlsxFilter"
        $dialog.DefaultExt = "xlsx"
    }

    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        Set-Status (Get-UiText "Status.ExportCancelled") "Info"
        return
    }

    try {
        Set-Status (Get-UiText "Status.Exporting" @($rowsToExport.Count, $Format)) "Info"
        if ($Format -eq "CSV") { Export-ManagedAccountsToCsv -Rows $rowsToExport -Path $dialog.FileName }
        else { Export-ManagedAccountsToXlsx -Rows $rowsToExport -Path $dialog.FileName }
        Set-Status (Get-UiText "Status.ExportReady" @($dialog.FileName)) "Ok"
        Show-InfoBox (Get-UiText "Status.ExportCompleted" @($dialog.FileName)) (Get-UiText "Status.ExportCompletedTitle")
    }
    catch {
        $msg = $_.Exception.Message
        Set-Status (Get-UiText "Status.ExportError" @($msg)) "Error"
        Show-ErrorBox (Get-UiText "Status.ExportFailed" @($msg)) (Get-UiText "Status.ExportErrorTitle")
    }
}

function Copy-SelectedLoginsToClipboard {
    try {
        if ($gridManaged.SelectedRows.Count -eq 0) {
            Show-InfoBox (Get-UiText "Status.SelectRow") (Get-UiText "Dialog.NoSelection")
            return
        }

        $logins = @()
        foreach ($row in $gridManaged.SelectedRows) {
            if ($null -ne $row.Cells["SamAccountName"].Value) { $logins += [string]$row.Cells["SamAccountName"].Value }
        }
        $text = ($logins | Sort-Object) -join [Environment]::NewLine
        if (-not (Is-Blank $text)) {
            [System.Windows.Forms.Clipboard]::SetText($text)
            Set-Status (Get-UiText "Status.LoginsCopied" @($logins.Count)) "Ok"
        }
    }
    catch {
        Set-Status (Get-UiText "Status.ClipboardFailed" @($_.Exception.Message)) "Error"
    }
}

# ==================================================
# GUI
# ==================================================

if (-not (Select-UiLanguage)) { return }
Show-WinSplash -Milliseconds 3000 -Title "ADKombajn" -Subtitle (Get-UiText "Splash.Subtitle") -Version $script:AppVersion -Author (Get-UiText "Splash.Author" @($script:AppAuthor))

$form = New-Object System.Windows.Forms.Form
$script:MainForm = $form
$form.Text = Get-UiText "App.WindowTitle" @($script:AppName, $script:AppVersion)
$form.StartPosition = "CenterScreen"
$form.Size = New-Size 1240 780
$form.MinimumSize = New-Size 1120 700
$form.BackColor = $script:Theme.Back
$form.Font = New-UiFont 9
$form.KeyPreview = $true
Set-DoubleBuffered $form
Apply-AppWindowIcon $form

# Global GUI exception handler to avoid displaying the raw .NET error dialog.
try {
    [System.Windows.Forms.Application]::add_ThreadException({
        param($sender, $e)
        $msg = Get-UiText "Error.GuiUnhandled" @($e.Exception.Message)
        Set-Status $msg "Error"
        Show-ErrorBox $msg (Get-UiText "Error.AppTitle")
    })
}
catch { }

$header = New-Object System.Windows.Forms.Panel
$header.Dock = [System.Windows.Forms.DockStyle]::Top
$header.Height = 94
$header.BackColor = [System.Drawing.Color]::FromArgb(18, 66, 55)
Set-DoubleBuffered $header
$header.Add_Paint({
    param($sender, $e)

    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    $rect = New-Object System.Drawing.Rectangle(0, 0, $sender.Width, $sender.Height)
    $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, [System.Drawing.Color]::FromArgb(18, 66, 55), [System.Drawing.Color]::FromArgb(38, 145, 94), 0.0)
    $g.FillRectangle($bg, $rect)
    $bg.Dispose()

    if ($null -ne $script:BrandImage) {
        $g.DrawImage($script:BrandImage, (New-Object System.Drawing.Rectangle(22, 9, 124, 76)))
    }

    $titleFont = New-Object System.Drawing.Font("Segoe UI Semibold", 22, [System.Drawing.FontStyle]::Regular)
    $subFont = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Regular)
    $authorFont = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Regular)
    $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $soft = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(222, 245, 232))
    $muted = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(196, 231, 212))
    $g.DrawString("ADKombajn", $titleFont, $white, 160, 15)
    $g.DrawString((Get-UiText "Header.Subtitle"), $subFont, $soft, 163, 58)
    $authorText = Get-UiText "Header.Author" @($script:AppAuthor)
    $size = $g.MeasureString($authorText, $authorFont)
    $g.DrawString($authorText, $authorFont, $muted, ($sender.Width - $size.Width - 22), 64)
    $titleFont.Dispose(); $subFont.Dispose(); $authorFont.Dispose(); $white.Dispose(); $soft.Dispose(); $muted.Dispose()
})

$btnExit = New-Object System.Windows.Forms.Button
$btnExit.Name = "btnExit"
$btnExit.Text = "$([char]0x23FB)  $(Get-UiText "Common.Exit")"
$btnExit.Size = New-Size 118 34
$btnExit.Location = New-Point 0 16
$btnExit.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$btnExit.Font = New-UiFont 9.5 ([System.Drawing.FontStyle]::Bold)
$btnExit.ForeColor = [System.Drawing.Color]::White
$btnExit.BackColor = [System.Drawing.Color]::FromArgb(21, 91, 64)
$btnExit.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnExit.FlatAppearance.BorderSize = 1
$btnExit.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(174, 229, 199)
$btnExit.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(35, 125, 84)
$btnExit.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(12, 68, 48)
$btnExit.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnExit.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$btnExit.UseVisualStyleBackColor = $false
$btnExit.TabStop = $false
$btnExit.AccessibleName = Get-UiText "Common.Exit"

$positionExitButton = {
    $x = [Math]::Max(0, $header.ClientSize.Width - $btnExit.Width - 22)
    $btnExit.Location = New-Point $x 16
    # The header is custom-painted, so resize must repaint its entire surface.
    $header.Invalidate($true)
}
$header.Add_Resize($positionExitButton)
[void]$header.Controls.Add($btnExit)
& $positionExitButton

$contextPanel = New-Object System.Windows.Forms.Panel
$contextPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$contextPanel.Height = 92
$contextPanel.Padding = New-Object System.Windows.Forms.Padding(14, 10, 14, 8)
$contextPanel.BackColor = $script:Theme.Back

$grpContext = New-CardGroup (Get-UiText "Context.Title") 14 8 1072 74
$grpContext.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

$lblDomain = New-Label (Get-UiText "Context.Domain") 18 31 90 22 9 ([System.Drawing.FontStyle]::Regular)
$txtDomain = New-TextBoxEx 112 28 245 $false
if (-not (Is-Blank $env:USERDNSDOMAIN)) { $txtDomain.Text = $env:USERDNSDOMAIN } else { $txtDomain.Text = $env:USERDOMAIN }

$lblLogin = New-Label (Get-UiText "Context.AccountLogin") 382 31 90 22 9 ([System.Drawing.FontStyle]::Regular)
$txtLogin = New-TextBoxEx 470 28 220 $false

$chkUseLdaps = New-Object System.Windows.Forms.CheckBox
$chkUseLdaps.Text = "LDAPS 636"
$chkUseLdaps.Location = New-Point 720 30
$chkUseLdaps.AutoSize = $true
$chkUseLdaps.Font = New-UiFont 9
$chkUseLdaps.ForeColor = $script:Theme.Text

$lblMode = New-Label (Get-UiText "Context.Mode") 808 31 245 22 8.5 ([System.Drawing.FontStyle]::Italic)
$lblMode.ForeColor = $script:Theme.Muted
$lblMode.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right

$grpContext.Controls.AddRange(@($lblDomain, $txtDomain, $lblLogin, $txtLogin, $chkUseLdaps, $lblMode))
$contextPanel.Controls.Add($grpContext)

try {
    $tabs = New-Object KombajnColorTabControlV21
}
catch {
    $tabs = New-Object System.Windows.Forms.TabControl
}
$tabs.Dock = [System.Windows.Forms.DockStyle]::Fill
$tabs.Font = New-UiFont 9.5 ([System.Drawing.FontStyle]::Regular)
$tabs.Padding = New-Point 14 5
try {
    $tabs.ItemSize = New-Size 136 34
    $tabs.SizeMode = [System.Windows.Forms.TabSizeMode]::Normal
}
catch { }

$tabValidate = New-Object System.Windows.Forms.TabPage
$tabValidate.Text = Get-UiText "Tab.ValidatePassword"
$tabValidate.BackColor = $script:Theme.Back

$tabChange = New-Object System.Windows.Forms.TabPage
$tabChange.Text = Get-UiText "Tab.ChangePassword"
$tabChange.BackColor = $script:Theme.Back

$tabManager = New-Object System.Windows.Forms.TabPage
$tabManager.Text = Get-UiText "Tab.ManagerAccounts"
$tabManager.BackColor = $script:Theme.Back

$tabAccountProps = New-Object System.Windows.Forms.TabPage
$tabAccountProps.Text = Get-UiText "Tab.AccountProperties"
$tabAccountProps.BackColor = $script:Theme.Back

$tabAccountGroups = New-Object System.Windows.Forms.TabPage
$tabAccountGroups.Text = Get-UiText "Tab.AccountGroups"
$tabAccountGroups.BackColor = $script:Theme.Back

$tabGroupMembers = New-Object System.Windows.Forms.TabPage
$tabGroupMembers.Text = Get-UiText "Tab.GroupMembers"
$tabGroupMembers.BackColor = $script:Theme.Back

$tabManagedGroups = New-Object System.Windows.Forms.TabPage
$tabManagedGroups.Text = Get-UiText "Tab.ManagedGroups"
$tabManagedGroups.BackColor = $script:Theme.Back

$tabLog = New-Object System.Windows.Forms.TabPage
$tabLog.Text = Get-UiText "Tab.Log"
$tabLog.BackColor = $script:Theme.Back

[void]$tabs.TabPages.Add($tabValidate)
[void]$tabs.TabPages.Add($tabChange)
[void]$tabs.TabPages.Add($tabAccountProps)
[void]$tabs.TabPages.Add($tabAccountGroups)
[void]$tabs.TabPages.Add($tabGroupMembers)
[void]$tabs.TabPages.Add($tabManagedGroups)
[void]$tabs.TabPages.Add($tabManager)
[void]$tabs.TabPages.Add($tabLog)

$script:PreservedAccountLogin = ""
$script:IsAccountLoginSuppressed = $false

$tabs.Add_SelectedIndexChanged({
    $isGroupMembersTab = ($tabs.SelectedTab -eq $tabGroupMembers)

    if ($isGroupMembersTab -and -not $script:IsAccountLoginSuppressed) {
        $script:PreservedAccountLogin = $txtLogin.Text
        $txtLogin.Clear()
        $txtLogin.Enabled = $false
        $lblLogin.Enabled = $false
        $script:IsAccountLoginSuppressed = $true
        return
    }

    if (-not $isGroupMembersTab -and $script:IsAccountLoginSuppressed) {
        $txtLogin.Enabled = $true
        $lblLogin.Enabled = $true
        $txtLogin.Text = $script:PreservedAccountLogin
        $script:IsAccountLoginSuppressed = $false
    }
})

# ---- Password validation tab ----
$grpValidate = New-CardGroup (Get-UiText "Validation.Title") 18 18 1042 145
$grpValidate.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

$lblValidatePassword = New-Label (Get-UiText "Validation.Password") 18 40 100 22
$txtValidatePassword = New-TextBoxEx 130 37 310 $true

$chkShowValidatePassword = New-Object System.Windows.Forms.CheckBox
$chkShowValidatePassword.Text = Get-UiText "Validation.ShowPassword"
$chkShowValidatePassword.Location = New-Point 460 40
$chkShowValidatePassword.AutoSize = $true
$chkShowValidatePassword.Font = New-UiFont 9
$chkShowValidatePassword.ForeColor = $script:Theme.Text

$btnValidate = New-FlatButton (Get-UiText "Validation.Check") 130 82 118 34
$btnClearValidate = New-SoftButton (Get-UiText "Common.Clear") 258 82 118 34
$lblValidateHint = New-Label (Get-UiText "Validation.Hint") 460 85 535 22 8.5 ([System.Drawing.FontStyle]::Italic)
$lblValidateHint.ForeColor = $script:Theme.Muted
$lblValidateHint.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$grpValidate.Controls.AddRange(@($lblValidatePassword, $txtValidatePassword, $chkShowValidatePassword, $btnValidate, $btnClearValidate, $lblValidateHint))

$grpLogValidate = New-CardGroup (Get-UiText "Common.Log") 18 185 1042 415
$grpLogValidate.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom

$txtLogValidate = New-Object System.Windows.Forms.TextBox
$txtLogValidate.Location = New-Point 16 26
$txtLogValidate.Size = New-Size 1010 360
$txtLogValidate.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
$txtLogValidate.Multiline = $true
$txtLogValidate.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$txtLogValidate.ReadOnly = $true
$txtLogValidate.BackColor = [System.Drawing.Color]::FromArgb(250, 252, 255)
$txtLogValidate.Font = New-Object System.Drawing.Font("Consolas", 9)
$txtLogValidate.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$btnClearLogValidate = New-SoftButton (Get-UiText "Common.ClearLog") 906 386 120 28
$btnClearLogValidate.Anchor = [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
$grpLogValidate.Controls.AddRange(@($txtLogValidate, $btnClearLogValidate))

# ---- Password change tab ----
$grpChange = New-CardGroup (Get-UiText "Change.Title") 18 18 1042 210
$grpChange.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

$lblOldPassword = New-Label (Get-UiText "Change.OldPassword") 18 38 105 22
$txtOldPassword = New-TextBoxEx 135 35 310 $true
$lblNewPassword = New-Label (Get-UiText "Change.NewPassword") 18 75 105 22
$txtNewPassword = New-TextBoxEx 135 72 310 $true
$lblRepeatPassword = New-Label (Get-UiText "Change.RepeatPassword") 18 112 105 22
$txtRepeatPassword = New-TextBoxEx 135 109 310 $true

$chkShowPasswords = New-Object System.Windows.Forms.CheckBox
$chkShowPasswords.Text = Get-UiText "Change.ShowPasswords"
$chkShowPasswords.Location = New-Point 470 37
$chkShowPasswords.AutoSize = $true
$chkShowPasswords.Font = New-UiFont 9
$chkShowPasswords.ForeColor = $script:Theme.Text

$btnChange = New-FlatButton (Get-UiText "Change.Button") 135 153 140 36 $script:Theme.Accent ([System.Drawing.Color]::White)
$btnClearChange = New-SoftButton (Get-UiText "Common.Clear") 285 153 110 36
$lblChangeHint = New-Label (Get-UiText "Change.Hint") 470 75 535 22 8.5 ([System.Drawing.FontStyle]::Italic)
$lblChangeHint.ForeColor = $script:Theme.Muted
$lblChangeHint.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$grpChange.Controls.AddRange(@($lblOldPassword, $txtOldPassword, $lblNewPassword, $txtNewPassword, $lblRepeatPassword, $txtRepeatPassword, $chkShowPasswords, $btnChange, $btnClearChange, $lblChangeHint))

$grpLogChange = New-CardGroup (Get-UiText "Common.Log") 18 245 1042 355
$grpLogChange.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom

$txtLogChange = New-Object System.Windows.Forms.TextBox
$txtLogChange.Location = New-Point 16 26
$txtLogChange.Size = New-Size 1010 300
$txtLogChange.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
$txtLogChange.Multiline = $true
$txtLogChange.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$txtLogChange.ReadOnly = $true
$txtLogChange.BackColor = [System.Drawing.Color]::FromArgb(250, 252, 255)
$txtLogChange.Font = New-Object System.Drawing.Font("Consolas", 9)
$txtLogChange.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$btnClearLogChange = New-SoftButton (Get-UiText "Common.ClearLog") 906 326 120 28
$btnClearLogChange.Anchor = [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
$grpLogChange.Controls.AddRange(@($txtLogChange, $btnClearLogChange))

# ---- Log tab ----
$grpLogGlobal = New-CardGroup (Get-UiText "Log.Events") 18 18 1042 582
$grpLogGlobal.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom

$txtLogMain = New-Object System.Windows.Forms.TextBox
$txtLogMain.Location = New-Point 16 26
$txtLogMain.Size = New-Size 1010 505
$txtLogMain.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
$txtLogMain.Multiline = $true
$txtLogMain.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$txtLogMain.ReadOnly = $true
$txtLogMain.BackColor = [System.Drawing.Color]::FromArgb(250, 252, 255)
$txtLogMain.Font = New-Object System.Drawing.Font("Consolas", 9)
$txtLogMain.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

$btnCopyLogMain = New-SoftButton (Get-UiText "Common.CopyLog") 770 540 120 28
$btnCopyLogMain.Anchor = [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom

$btnClearLogMain = New-SoftButton (Get-UiText "Common.ClearLog") 906 540 120 28
$btnClearLogMain.Anchor = [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom

$grpLogGlobal.Controls.AddRange(@($txtLogMain, $btnCopyLogMain, $btnClearLogMain))

$script:txtLog = $txtLogMain
$script:txtLogs = @($txtLogMain)

$tabValidate.Controls.AddRange(@($grpValidate))
$tabChange.Controls.AddRange(@($grpChange))
$tabLog.Controls.Add($grpLogGlobal)

# ---- Account properties tab ----
$accountPropsTop = New-Object System.Windows.Forms.Panel
$accountPropsTop.Dock = [System.Windows.Forms.DockStyle]::Top
$accountPropsTop.Height = 90
$accountPropsTop.BackColor = $script:Theme.Back

$btnGetAccountProps = New-FlatButton (Get-UiText "AccountProperties.Get") 18 16 160 34
$btnClearAccountProps = New-SoftButton (Get-UiText "Common.Clear") 188 16 95 34
$btnCopyAccountProps = New-SoftButton (Get-UiText "Common.CopySelected") 293 16 140 34
$btnCopyAllAccountProps = New-SoftButton (Get-UiText "Common.CopyAll") 443 16 130 34

$lblAccountPropsInfo = New-Label (Get-UiText "AccountProperties.Info") 18 58 720 22 8.5 ([System.Drawing.FontStyle]::Italic)
$lblAccountPropsInfo.ForeColor = $script:Theme.Muted

$lblAccountPropsCount = New-Label (Get-UiText "AccountProperties.CountEmpty") 760 22 300 24 10 ([System.Drawing.FontStyle]::Bold)
$lblAccountPropsCount.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$lblAccountPropsCount.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight

$accountPropsTop.Controls.AddRange(@($btnGetAccountProps, $btnClearAccountProps, $btnCopyAccountProps, $btnCopyAllAccountProps, $lblAccountPropsInfo, $lblAccountPropsCount))

$gridAccountProps = New-Object System.Windows.Forms.DataGridView
$gridAccountProps.Dock = [System.Windows.Forms.DockStyle]::Fill
$gridAccountProps.AutoGenerateColumns = $false
$gridAccountProps.ColumnHeadersVisible = $true
$gridAccountProps.BackgroundColor = [System.Drawing.Color]::White
$gridAccountProps.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$gridAccountProps.ReadOnly = $true
$gridAccountProps.AllowUserToAddRows = $false
$gridAccountProps.AllowUserToDeleteRows = $false
$gridAccountProps.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
$gridAccountProps.MultiSelect = $true
$gridAccountProps.RowHeadersVisible = $false
$gridAccountProps.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
$gridAccountProps.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
$gridAccountProps.Font = New-UiFont 9
$gridAccountProps.ColumnHeadersDefaultCellStyle.Font = New-UiFont 9 ([System.Drawing.FontStyle]::Bold)
$gridAccountProps.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(0, 100, 96)
$gridAccountProps.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
$gridAccountProps.ColumnHeadersDefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(0, 100, 96)
$gridAccountProps.EnableHeadersVisualStyles = $false
$gridAccountProps.AlternatingRowsDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(245, 249, 253)
$gridAccountProps.GridColor = $script:Theme.Border
$gridAccountProps.RowTemplate.Height = 25
$gridAccountProps.DefaultCellStyle.WrapMode = [System.Windows.Forms.DataGridViewTriState]::False
Set-DoubleBuffered $gridAccountProps

[void]$gridAccountProps.Columns.Add((New-TextGridColumn "Attribute" (Get-UiText "Column.Attribute") 230 $true))
[void]$gridAccountProps.Columns.Add((New-TextGridColumn "Value" (Get-UiText "Column.Value") 720 $true))
[void]$gridAccountProps.Columns.Add((New-TextGridColumn "Count" (Get-UiText "Column.Count") 60 $true))
$gridAccountProps.Columns[0].FillWeight = 24
$gridAccountProps.Columns[1].FillWeight = 70
$gridAccountProps.Columns[2].FillWeight = 6

$tabAccountProps.Controls.Add($gridAccountProps)
$tabAccountProps.Controls.Add($accountPropsTop)

# ---- Account groups tab ----
$accountGroupsTop = New-Object System.Windows.Forms.Panel
$accountGroupsTop.Dock = [System.Windows.Forms.DockStyle]::Top
$accountGroupsTop.Height = 90
$accountGroupsTop.BackColor = $script:Theme.Back

$btnGetAccountGroups = New-FlatButton (Get-UiText "AccountGroups.Get") 18 16 135 34
$btnClearAccountGroups = New-SoftButton (Get-UiText "Common.Clear") 163 16 95 34
$btnCopyAccountGroups = New-SoftButton (Get-UiText "Common.CopySelected") 268 16 140 34
$btnCopyAllAccountGroups = New-SoftButton (Get-UiText "Common.CopyAll") 418 16 130 34

$lblAccountGroupsInfo = New-Label (Get-UiText "AccountGroups.Info") 18 58 720 22 8.5 ([System.Drawing.FontStyle]::Italic)
$lblAccountGroupsInfo.ForeColor = $script:Theme.Muted

$lblAccountGroupsCount = New-Label (Get-UiText "Groups.CountEmpty") 760 22 300 24 10 ([System.Drawing.FontStyle]::Bold)
$lblAccountGroupsCount.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$lblAccountGroupsCount.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight

$accountGroupsTop.Controls.AddRange(@($btnGetAccountGroups, $btnClearAccountGroups, $btnCopyAccountGroups, $btnCopyAllAccountGroups, $lblAccountGroupsInfo, $lblAccountGroupsCount))

$gridAccountGroups = New-Object System.Windows.Forms.DataGridView
$gridAccountGroups.Dock = [System.Windows.Forms.DockStyle]::Fill
$gridAccountGroups.AutoGenerateColumns = $false
$gridAccountGroups.ColumnHeadersVisible = $true
$gridAccountGroups.BackgroundColor = [System.Drawing.Color]::White
$gridAccountGroups.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$gridAccountGroups.ReadOnly = $true
$gridAccountGroups.AllowUserToAddRows = $false
$gridAccountGroups.AllowUserToDeleteRows = $false
$gridAccountGroups.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
$gridAccountGroups.MultiSelect = $true
$gridAccountGroups.RowHeadersVisible = $false
$gridAccountGroups.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
$gridAccountGroups.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
$gridAccountGroups.Font = New-UiFont 9
$gridAccountGroups.ColumnHeadersDefaultCellStyle.Font = New-UiFont 9 ([System.Drawing.FontStyle]::Bold)
$gridAccountGroups.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(92, 118, 28)
$gridAccountGroups.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
$gridAccountGroups.ColumnHeadersDefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(92, 118, 28)
$gridAccountGroups.EnableHeadersVisualStyles = $false
$gridAccountGroups.AlternatingRowsDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(246, 250, 240)
$gridAccountGroups.GridColor = $script:Theme.Border
$gridAccountGroups.RowTemplate.Height = 25
Set-DoubleBuffered $gridAccountGroups

[void]$gridAccountGroups.Columns.Add((New-TextGridColumn "Name" (Get-UiText "Column.Name") 190 $true))
[void]$gridAccountGroups.Columns.Add((New-TextGridColumn "SamAccountName" (Get-UiText "Column.GroupLogin") 150 $true))
[void]$gridAccountGroups.Columns.Add((New-TextGridColumn "DisplayName" (Get-UiText "Column.DisplayName") 190 $true))
[void]$gridAccountGroups.Columns.Add((New-TextGridColumn "Type" (Get-UiText "Column.Type") 95 $true))
[void]$gridAccountGroups.Columns.Add((New-TextGridColumn "Scope" (Get-UiText "Column.Scope") 95 $true))
[void]$gridAccountGroups.Columns.Add((New-TextGridColumn "Source" (Get-UiText "Column.Source") 115 $true))
[void]$gridAccountGroups.Columns.Add((New-TextGridColumn "Description" (Get-UiText "Column.Description") 260 $true))
[void]$gridAccountGroups.Columns.Add((New-TextGridColumn "DistinguishedName" "DN" 300 $false))

$tabAccountGroups.Controls.Add($gridAccountGroups)
$tabAccountGroups.Controls.Add($accountGroupsTop)



# ---- Group members tab ----
$groupMembersTop = New-Object System.Windows.Forms.Panel
$groupMembersTop.Dock = [System.Windows.Forms.DockStyle]::Top
$groupMembersTop.Height = 118
$groupMembersTop.BackColor = $script:Theme.Back

$lblGroupMembersGroup = New-Label (Get-UiText "GroupMembers.Group") 18 18 80 24
$txtGroupMembersGroup = New-TextBoxEx 105 15 330 $false

$btnGetGroupMembers = New-FlatButton (Get-UiText "GroupMembers.Get") 455 14 150 34
$btnClearGroupMembers = New-SoftButton (Get-UiText "Common.Clear") 615 14 95 34
$btnCopyGroupMembers = New-SoftButton (Get-UiText "Common.CopySelected") 720 14 140 34
$btnCopyAllGroupMembers = New-SoftButton (Get-UiText "Common.CopyAll") 870 14 130 34

$lblGroupMembersInfo = New-Label (Get-UiText "GroupMembers.Info") 18 58 960 42 8.5 ([System.Drawing.FontStyle]::Italic)
$lblGroupMembersInfo.ForeColor = $script:Theme.Muted

$lblGroupMembersCount = New-Label (Get-UiText "GroupMembers.CountEmpty") 760 90 300 24 10 ([System.Drawing.FontStyle]::Bold)
$lblGroupMembersCount.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$lblGroupMembersCount.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight

$groupMembersTop.Controls.AddRange(@($lblGroupMembersGroup, $txtGroupMembersGroup, $btnGetGroupMembers, $btnClearGroupMembers, $btnCopyGroupMembers, $btnCopyAllGroupMembers, $lblGroupMembersInfo, $lblGroupMembersCount))

$gridGroupMembers = New-Object System.Windows.Forms.DataGridView
$gridGroupMembers.Dock = [System.Windows.Forms.DockStyle]::Fill
$gridGroupMembers.AutoGenerateColumns = $false
$gridGroupMembers.ColumnHeadersVisible = $true
$gridGroupMembers.BackgroundColor = [System.Drawing.Color]::White
$gridGroupMembers.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$gridGroupMembers.ReadOnly = $true
$gridGroupMembers.AllowUserToAddRows = $false
$gridGroupMembers.AllowUserToDeleteRows = $false
$gridGroupMembers.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
$gridGroupMembers.MultiSelect = $true
$gridGroupMembers.RowHeadersVisible = $false
$gridGroupMembers.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
$gridGroupMembers.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
$gridGroupMembers.Font = New-UiFont 9
$gridGroupMembers.ColumnHeadersDefaultCellStyle.Font = New-UiFont 9 ([System.Drawing.FontStyle]::Bold)
$gridGroupMembers.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(174, 48, 82)
$gridGroupMembers.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
$gridGroupMembers.ColumnHeadersDefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(174, 48, 82)
$gridGroupMembers.EnableHeadersVisualStyles = $false
$gridGroupMembers.AlternatingRowsDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(253, 244, 247)
$gridGroupMembers.GridColor = $script:Theme.Border
$gridGroupMembers.RowTemplate.Height = 25
Set-DoubleBuffered $gridGroupMembers

[void]$gridGroupMembers.Columns.Add((New-TextGridColumn "Name" (Get-UiText "Column.Name") 190 $true))
[void]$gridGroupMembers.Columns.Add((New-TextGridColumn "SamAccountName" (Get-UiText "Column.Login") 150 $true))
[void]$gridGroupMembers.Columns.Add((New-TextGridColumn "DisplayName" (Get-UiText "Column.DisplayName") 190 $true))
[void]$gridGroupMembers.Columns.Add((New-TextGridColumn "ObjectType" (Get-UiText "Column.Type") 95 $true))
[void]$gridGroupMembers.Columns.Add((New-TextGridColumn "Enabled" "Enabled" 80 $true))
[void]$gridGroupMembers.Columns.Add((New-TextGridColumn "UserPrincipalName" "UPN" 210 $true))
[void]$gridGroupMembers.Columns.Add((New-TextGridColumn "Description" (Get-UiText "Column.Description") 260 $true))
[void]$gridGroupMembers.Columns.Add((New-TextGridColumn "DistinguishedName" "DN" 320 $false))

$tabGroupMembers.Controls.Add($gridGroupMembers)
$tabGroupMembers.Controls.Add($groupMembersTop)



# ---- Managed groups tab ----
$managedGroupsTop = New-Object System.Windows.Forms.Panel
$managedGroupsTop.Dock = [System.Windows.Forms.DockStyle]::Top
$managedGroupsTop.Height = 90
$managedGroupsTop.BackColor = $script:Theme.Back

$btnGetManagedGroups = New-FlatButton (Get-UiText "ManagedGroups.Get") 18 16 135 34
$btnClearManagedGroups = New-SoftButton (Get-UiText "Common.Clear") 163 16 95 34
$btnCopyManagedGroups = New-SoftButton (Get-UiText "Common.CopySelected") 268 16 140 34
$btnCopyAllManagedGroups = New-SoftButton (Get-UiText "Common.CopyAll") 418 16 130 34

$lblManagedGroupsInfo = New-Label (Get-UiText "ManagedGroups.Info") 18 58 820 22 8.5 ([System.Drawing.FontStyle]::Italic)
$lblManagedGroupsInfo.ForeColor = $script:Theme.Muted

$lblManagedGroupsCount = New-Label (Get-UiText "Groups.CountEmpty") 860 22 220 24 10 ([System.Drawing.FontStyle]::Bold)
$lblManagedGroupsCount.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$lblManagedGroupsCount.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight

$managedGroupsTop.Controls.AddRange(@($btnGetManagedGroups, $btnClearManagedGroups, $btnCopyManagedGroups, $btnCopyAllManagedGroups, $lblManagedGroupsInfo, $lblManagedGroupsCount))

$gridManagedGroups = New-Object System.Windows.Forms.DataGridView
$gridManagedGroups.Dock = [System.Windows.Forms.DockStyle]::Fill
$gridManagedGroups.AutoGenerateColumns = $false
$gridManagedGroups.ColumnHeadersVisible = $true
$gridManagedGroups.BackgroundColor = [System.Drawing.Color]::White
$gridManagedGroups.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$gridManagedGroups.ReadOnly = $true
$gridManagedGroups.AllowUserToAddRows = $false
$gridManagedGroups.AllowUserToDeleteRows = $false
$gridManagedGroups.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
$gridManagedGroups.MultiSelect = $true
$gridManagedGroups.RowHeadersVisible = $false
$gridManagedGroups.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
$gridManagedGroups.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
$gridManagedGroups.Font = New-UiFont 9
$gridManagedGroups.ColumnHeadersDefaultCellStyle.Font = New-UiFont 9 ([System.Drawing.FontStyle]::Bold)
$gridManagedGroups.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(82, 104, 201)
$gridManagedGroups.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
$gridManagedGroups.ColumnHeadersDefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(82, 104, 201)
$gridManagedGroups.EnableHeadersVisualStyles = $false
$gridManagedGroups.AlternatingRowsDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(244, 245, 255)
$gridManagedGroups.GridColor = $script:Theme.Border
$gridManagedGroups.RowTemplate.Height = 25
Set-DoubleBuffered $gridManagedGroups

[void]$gridManagedGroups.Columns.Add((New-TextGridColumn "Name" (Get-UiText "Column.Name") 190 $true))
[void]$gridManagedGroups.Columns.Add((New-TextGridColumn "SamAccountName" (Get-UiText "Column.GroupLogin") 150 $true))
[void]$gridManagedGroups.Columns.Add((New-TextGridColumn "DisplayName" (Get-UiText "Column.DisplayName") 190 $true))
[void]$gridManagedGroups.Columns.Add((New-TextGridColumn "Type" (Get-UiText "Column.Type") 95 $true))
[void]$gridManagedGroups.Columns.Add((New-TextGridColumn "Scope" (Get-UiText "Column.Scope") 95 $true))
[void]$gridManagedGroups.Columns.Add((New-TextGridColumn "Source" (Get-UiText "Column.Source") 115 $true))
[void]$gridManagedGroups.Columns.Add((New-TextGridColumn "Description" (Get-UiText "Column.Description") 260 $true))
[void]$gridManagedGroups.Columns.Add((New-TextGridColumn "DistinguishedName" "DN" 300 $false))

$tabManagedGroups.Controls.Add($gridManagedGroups)
$tabManagedGroups.Controls.Add($managedGroupsTop)


# ---- Manager accounts tab ----
$managerTop = New-Object System.Windows.Forms.Panel
$managerTop.Dock = [System.Windows.Forms.DockStyle]::Top
$managerTop.Height = 92
$managerTop.BackColor = $script:Theme.Back

$btnManaged = New-FlatButton (Get-UiText "ManagerAccounts.Get") 18 16 135 34
$btnClearManaged = New-SoftButton (Get-UiText "Common.Clear") 163 16 95 34
$btnExportCsv = New-SoftButton (Get-UiText "ManagerAccounts.ExportCsv") 268 16 112 34
$btnExportXlsx = New-SoftButton (Get-UiText "ManagerAccounts.ExportXlsx") 390 16 118 34
$btnCopyLogins = New-SoftButton (Get-UiText "ManagerAccounts.CopyLogins") 518 16 120 34

$lblManagedFilter = New-Label (Get-UiText "ManagerAccounts.Show") 18 60 50 22
$rdoManagedAll = New-Object System.Windows.Forms.RadioButton
$rdoManagedAll.Text = Get-UiText "Filter.All"
$rdoManagedAll.Location = New-Point 72 58
$rdoManagedAll.AutoSize = $true
$rdoManagedAll.Checked = $true
$rdoManagedAll.Font = New-UiFont 9
$rdoManagedActive = New-Object System.Windows.Forms.RadioButton
$rdoManagedActive.Text = Get-UiText "Filter.Active"
$rdoManagedActive.Location = New-Point 162 58
$rdoManagedActive.AutoSize = $true
$rdoManagedActive.Font = New-UiFont 9
$rdoManagedInactive = New-Object System.Windows.Forms.RadioButton
$rdoManagedInactive.Text = Get-UiText "Filter.Inactive"
$rdoManagedInactive.Location = New-Point 242 58
$rdoManagedInactive.AutoSize = $true
$rdoManagedInactive.Font = New-UiFont 9

$lblSearch = New-Label (Get-UiText "ManagerAccounts.Search") 380 60 55 22
$txtManagedSearch = New-TextBoxEx 435 57 230 $false

$lblManagedCount = New-Label (Get-UiText "ManagerAccounts.CountEmpty") 700 22 360 24 10 ([System.Drawing.FontStyle]::Bold)
$lblManagedCount.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$lblManagedCount.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$lblManagedInfo = New-Label (Get-UiText "ManagerAccounts.ExportInfo") 700 56 360 22 8.5 ([System.Drawing.FontStyle]::Italic)
$lblManagedInfo.ForeColor = $script:Theme.Muted
$lblManagedInfo.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$lblManagedInfo.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight

$managerTop.Controls.AddRange(@($btnManaged, $btnClearManaged, $btnExportCsv, $btnExportXlsx, $btnCopyLogins, $lblManagedFilter, $rdoManagedAll, $rdoManagedActive, $rdoManagedInactive, $lblSearch, $txtManagedSearch, $lblManagedCount, $lblManagedInfo))

$gridManaged = New-Object System.Windows.Forms.DataGridView
$gridManaged.Dock = [System.Windows.Forms.DockStyle]::Fill
$gridManaged.AutoGenerateColumns = $false
$gridManaged.ColumnHeadersVisible = $true
$gridManaged.BackgroundColor = [System.Drawing.Color]::White
$gridManaged.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$gridManaged.ReadOnly = $true
$gridManaged.AllowUserToAddRows = $false
$gridManaged.AllowUserToDeleteRows = $false
$gridManaged.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
$gridManaged.MultiSelect = $true
$gridManaged.RowHeadersVisible = $false
$gridManaged.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
$gridManaged.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
$gridManaged.Font = New-UiFont 9
$gridManaged.ColumnHeadersDefaultCellStyle.Font = New-UiFont 9 ([System.Drawing.FontStyle]::Bold)
$gridManaged.ColumnHeadersDefaultCellStyle.BackColor = $script:Theme.Navy
$gridManaged.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
$gridManaged.ColumnHeadersDefaultCellStyle.SelectionBackColor = $script:Theme.Navy
$gridManaged.EnableHeadersVisualStyles = $false
$gridManaged.AlternatingRowsDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(245, 249, 253)
$gridManaged.GridColor = $script:Theme.Border
$gridManaged.RowTemplate.Height = 24
Set-DoubleBuffered $gridManaged

[void]$gridManaged.Columns.Add((New-TextGridColumn "SamAccountName" (Get-UiText "Column.Login") 120 $true))
[void]$gridManaged.Columns.Add((New-TextGridColumn "Name" (Get-UiText "Column.Name") 150 $true))
[void]$gridManaged.Columns.Add((New-TextGridColumn "DisplayName" (Get-UiText "Column.DisplayName") 185 $true))
[void]$gridManaged.Columns.Add((New-TextGridColumn "Enabled" (Get-UiText "Column.Enabled") 70 $true))
[void]$gridManaged.Columns.Add((New-TextGridColumn "UserPrincipalName" "UPN" 210 $true))
[void]$gridManaged.Columns.Add((New-TextGridColumn "Description" (Get-UiText "Column.Description") 260 $true))
[void]$gridManaged.Columns.Add((New-TextGridColumn "PasswordLastSet" (Get-UiText "Column.PasswordLastSet") 150 $true))
[void]$gridManaged.Columns.Add((New-TextGridColumn "DistinguishedName" "DN" 260 $false))


$tabManager.Controls.Add($gridManaged)
$tabManager.Controls.Add($managerTop)

function Set-AccountPropertiesGrid {
    param([object[]]$Rows)

    $gridAccountProps.SuspendLayout()
    try {
        $gridAccountProps.Rows.Clear()
        if ($null -ne $Rows) {
            foreach ($row in $Rows) {
                [void]$gridAccountProps.Rows.Add(
                    [string]$row.Attribute,
                    [string]$row.Value,
                    [string]$row.Count
                )
            }
        }
        $lblAccountPropsCount.Text = Get-UiText "AccountProperties.Count" @(@($Rows).Count)
        $gridAccountProps.ClearSelection()
    }
    finally {
        $gridAccountProps.ResumeLayout()
    }
}

function Convert-AccountPropertyRowsToClipboardText {
    param([object[]]$Rows)

    $lines = @()
    foreach ($row in @($Rows)) {
        if ($null -eq $row) { continue }
        $lines += ("{0}`t{1}`t{2}" -f [string]$row.Attribute, [string]$row.Value, [string]$row.Count)
    }
    return ($lines -join [Environment]::NewLine)
}

function Get-SelectedAccountPropertyRows {
    $rows = @()
    try {
        foreach ($gridRow in $gridAccountProps.SelectedRows) {
            if ($null -eq $gridRow -or $gridRow.IsNewRow) { continue }
            $rows += [PSCustomObject]@{
                Attribute = [string]$gridRow.Cells["Attribute"].Value
                Value     = [string]$gridRow.Cells["Value"].Value
                Count     = [int]$gridRow.Cells["Count"].Value
            }
        }
    }
    catch { }
    return @($rows | Sort-Object Attribute)
}

function Set-AccountGroupsGrid {
    param([object[]]$Rows)

    $gridAccountGroups.SuspendLayout()
    try {
        $gridAccountGroups.Rows.Clear()
        if ($null -ne $Rows) {
            foreach ($row in $Rows) {
                [void]$gridAccountGroups.Rows.Add(
                    [string]$row.Name,
                    [string]$row.SamAccountName,
                    [string]$row.DisplayName,
                    [string]$row.Type,
                    [string]$row.Scope,
                    [string]$row.Source,
                    [string]$row.Description,
                    [string]$row.DistinguishedName
                )
            }
        }
        $lblAccountGroupsCount.Text = Get-UiText "Groups.Count" @(@($Rows).Count)
        $gridAccountGroups.ClearSelection()
    }
    finally {
        $gridAccountGroups.ResumeLayout()
    }
}

function Convert-AccountGroupRowsToClipboardText {
    param([object[]]$Rows)

    $lines = @()
    foreach ($row in @($Rows)) {
        if ($null -eq $row) { continue }
        $lines += ("{0}`t{1}`t{2}`t{3}`t{4}`t{5}`t{6}`t{7}" -f `
            [string]$row.Name,
            [string]$row.SamAccountName,
            [string]$row.DisplayName,
            [string]$row.Type,
            [string]$row.Scope,
            [string]$row.Source,
            [string]$row.Description,
            [string]$row.DistinguishedName)
    }
    return ($lines -join [Environment]::NewLine)
}

function Get-SelectedAccountGroupRows {
    $rows = @()
    try {
        foreach ($gridRow in $gridAccountGroups.SelectedRows) {
            if ($null -eq $gridRow -or $gridRow.IsNewRow) { continue }
            $rows += [PSCustomObject]@{
                Name              = [string]$gridRow.Cells["Name"].Value
                SamAccountName    = [string]$gridRow.Cells["SamAccountName"].Value
                DisplayName       = [string]$gridRow.Cells["DisplayName"].Value
                Type              = [string]$gridRow.Cells["Type"].Value
                Scope             = [string]$gridRow.Cells["Scope"].Value
                Source            = [string]$gridRow.Cells["Source"].Value
                Description       = [string]$gridRow.Cells["Description"].Value
                DistinguishedName = [string]$gridRow.Cells["DistinguishedName"].Value
            }
        }
    }
    catch { }
    return @($rows | Sort-Object -Property @("Name", "SamAccountName"))
}


function Set-ManagedGroupsGrid {
    param([object[]]$Rows)

    $gridManagedGroups.SuspendLayout()
    try {
        $gridManagedGroups.Rows.Clear()
        if ($null -ne $Rows) {
            foreach ($row in $Rows) {
                [void]$gridManagedGroups.Rows.Add(
                    [string]$row.Name,
                    [string]$row.SamAccountName,
                    [string]$row.DisplayName,
                    [string]$row.Type,
                    [string]$row.Scope,
                    [string]$row.Source,
                    [string]$row.Description,
                    [string]$row.DistinguishedName
                )
            }
        }
        $lblManagedGroupsCount.Text = Get-UiText "Groups.Count" @(@($Rows).Count)
        $gridManagedGroups.ClearSelection()
    }
    finally {
        $gridManagedGroups.ResumeLayout()
    }
}

function Get-SelectedManagedGroupRows {
    $rows = @()
    try {
        foreach ($gridRow in $gridManagedGroups.SelectedRows) {
            if ($null -eq $gridRow -or $gridRow.IsNewRow) { continue }
            $rows += [PSCustomObject]@{
                Name              = [string]$gridRow.Cells["Name"].Value
                SamAccountName    = [string]$gridRow.Cells["SamAccountName"].Value
                DisplayName       = [string]$gridRow.Cells["DisplayName"].Value
                Type              = [string]$gridRow.Cells["Type"].Value
                Scope             = [string]$gridRow.Cells["Scope"].Value
                Source            = [string]$gridRow.Cells["Source"].Value
                Description       = [string]$gridRow.Cells["Description"].Value
                DistinguishedName = [string]$gridRow.Cells["DistinguishedName"].Value
            }
        }
    }
    catch { }
    return @($rows | Sort-Object -Property @("Name", "SamAccountName"))
}





function Set-DomainGroupMembersGrid {
    param([object[]]$Rows)

    $gridGroupMembers.SuspendLayout()
    try {
        $gridGroupMembers.Rows.Clear()
        if ($null -ne $Rows) {
            foreach ($row in $Rows) {
                [void]$gridGroupMembers.Rows.Add(
                    [string]$row.Name,
                    [string]$row.SamAccountName,
                    [string]$row.DisplayName,
                    [string]$row.ObjectType,
                    [string]$row.Enabled,
                    [string]$row.UserPrincipalName,
                    [string]$row.Description,
                    [string]$row.DistinguishedName
                )
            }
        }
        $lblGroupMembersCount.Text = Get-UiText "GroupMembers.Count" @(@($Rows).Count)
        $gridGroupMembers.ClearSelection()
    }
    finally {
        $gridGroupMembers.ResumeLayout()
    }
}

function Convert-DomainGroupMemberRowsToClipboardText {
    param([object[]]$Rows)

    $lines = @()
    foreach ($row in @($Rows)) {
        if ($null -eq $row) { continue }
        $lines += ("{0}`t{1}`t{2}`t{3}`t{4}`t{5}`t{6}`t{7}" -f `
            [string]$row.Name,
            [string]$row.SamAccountName,
            [string]$row.DisplayName,
            [string]$row.ObjectType,
            [string]$row.Enabled,
            [string]$row.UserPrincipalName,
            [string]$row.Description,
            [string]$row.DistinguishedName)
    }
    return ($lines -join [Environment]::NewLine)
}

function Get-SelectedDomainGroupMemberRows {
    $rows = @()
    try {
        foreach ($gridRow in $gridGroupMembers.SelectedRows) {
            if ($null -eq $gridRow -or $gridRow.IsNewRow) { continue }
            $rows += [PSCustomObject]@{
                Name              = [string]$gridRow.Cells["Name"].Value
                SamAccountName    = [string]$gridRow.Cells["SamAccountName"].Value
                DisplayName       = [string]$gridRow.Cells["DisplayName"].Value
                ObjectType        = [string]$gridRow.Cells["ObjectType"].Value
                Enabled           = [string]$gridRow.Cells["Enabled"].Value
                UserPrincipalName = [string]$gridRow.Cells["UserPrincipalName"].Value
                Description       = [string]$gridRow.Cells["Description"].Value
                DistinguishedName = [string]$gridRow.Cells["DistinguishedName"].Value
            }
        }
    }
    catch { }
    return @($rows | Sort-Object -Property @("ObjectType", "SamAccountName", "Name"))
}

$statusStrip = New-Object System.Windows.Forms.StatusStrip
$statusStrip.SizingGrip = $true
$statusStrip.BackColor = [System.Drawing.Color]::FromArgb(235, 241, 248)
$toolStatus = New-Object System.Windows.Forms.ToolStripStatusLabel
$script:StatusLabel = $toolStatus
$toolStatus.Text = Get-UiText "Status.ReadyShort"
$toolStatus.ForeColor = $script:Theme.Text
$toolStatus.Spring = $true
$toolStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
[void]$statusStrip.Items.Add($toolStatus)

$form.Controls.Add($tabs)
$form.Controls.Add($contextPanel)
$form.Controls.Add($header)
$form.Controls.Add($statusStrip)

# ==================================================
# Events
# ==================================================

$btnExit.Add_Click({
    $form.Close()
})

$btnClearLogMain.Add_Click({
    try {
        if ($null -ne $txtLogMain) { $txtLogMain.Clear() }
    }
    catch { }
    Set-Status (Get-UiText "Status.LogCleared") "Info" $false
})

$btnCopyLogMain.Add_Click({
    try {
        if ($null -eq $txtLogMain -or (Is-Blank $txtLogMain.Text)) {
            Set-Status (Get-UiText "Status.LogEmpty") "Warn"
            return
        }

        [System.Windows.Forms.Clipboard]::SetText($txtLogMain.Text)
        Set-Status (Get-UiText "Status.LogCopied") "Ok"
    }
    catch {
        Set-Status (Get-UiText "Status.LogCopyFailed" @($_.Exception.Message)) "Error"
    }
})

$btnClearValidate.Add_Click({
    $txtValidatePassword.Clear()
    Set-Status (Get-UiText "Status.ValidationPasswordCleared") "Info"
})

$btnClearChange.Add_Click({
    $txtOldPassword.Clear()
    $txtNewPassword.Clear()
    $txtRepeatPassword.Clear()
    Set-Status (Get-UiText "Status.ChangeFieldsCleared") "Info"
})

$chkShowValidatePassword.Add_CheckedChanged({
    $txtValidatePassword.UseSystemPasswordChar = -not $chkShowValidatePassword.Checked
})

$chkShowPasswords.Add_CheckedChanged({
    $show = $chkShowPasswords.Checked
    $txtOldPassword.UseSystemPasswordChar = -not $show
    $txtNewPassword.UseSystemPasswordChar = -not $show
    $txtRepeatPassword.UseSystemPasswordChar = -not $show
})

$btnValidate.Add_Click({
    $domain = $txtDomain.Text.Trim()
    $login = $txtLogin.Text.Trim()
    $password = $txtValidatePassword.Text
    $useLdaps = $chkUseLdaps.Checked
    $port = Get-LdapPortFromUi

    if ((Is-Blank $domain) -or (Is-Blank $login) -or (Is-Blank $password)) {
        Set-Status (Get-UiText "Status.EnterValidationData") "Error"
        return
    }

    try {
        $btnValidate.Enabled = $false
        Set-Status (Get-UiText "Status.ValidatingPassword" @($domain, $login)) "Info"
        $result = Test-AdPasswordNoRsat -DomainOrDc $domain -Login $login -Password $password -UseLdaps $useLdaps -Port $port

        if ($result.Success) {
            Set-Status (Get-UiText "Status.PasswordValid" @($domain, $login)) "Ok"
        }
        else {
            Set-Status (Get-UiText "Status.PasswordInvalid") "Error"
            Show-ErrorBox $result.Message (Get-UiText "Tab.ValidatePassword")
        }
    }
    finally {
        $btnValidate.Enabled = $true
    }
})

$btnChange.Add_Click({
    $domain = $txtDomain.Text.Trim()
    $login = $txtLogin.Text.Trim()
    $oldPassword = $txtOldPassword.Text
    $newPassword = $txtNewPassword.Text
    $repeatPassword = $txtRepeatPassword.Text
    $useLdaps = $chkUseLdaps.Checked
    $port = Get-LdapPortFromUi

    if ((Is-Blank $domain) -or (Is-Blank $login)) {
        Set-Status (Get-UiText "Status.EnterDomainLogin") "Error"
        return
    }
    if ((Is-Blank $oldPassword) -or (Is-Blank $newPassword) -or (Is-Blank $repeatPassword)) {
        Set-Status (Get-UiText "Status.EnterPasswordChangeData") "Error"
        return
    }
    if ($newPassword -ne $repeatPassword) {
        Set-Status (Get-UiText "Status.PasswordsDiffer") "Error"
        return
    }
    if ($oldPassword -eq $newPassword) {
        Set-Status (Get-UiText "Status.PasswordUnchanged") "Error"
        return
    }

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        (Get-UiText "Status.ConfirmPasswordChange" @($domain, $login)),
        (Get-UiText "Status.ConfirmPasswordChangeTitle"),
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
        Set-Status (Get-UiText "Status.PasswordChangeCancelled") "Info"
        return
    }

    try {
        $btnChange.Enabled = $false
        Set-Status (Get-UiText "Status.ChangingPassword" @($domain, $login)) "Info"
        $result = Change-AdAccountPasswordNoRsat -DomainOrDc $domain -Login $login -OldPassword $oldPassword -NewPassword $newPassword -UseLdaps $useLdaps -Port $port

        if ($result.Success) {
            Set-Status (Get-UiText "Status.PasswordChanged" @($domain, $login)) "Ok"
            $txtOldPassword.Clear()
            $txtNewPassword.Clear()
            $txtRepeatPassword.Clear()
        }
        else {
            Set-Status (Get-UiText "Status.PasswordChangeError" @($domain, $login)) "Error"
            Show-ErrorBox $result.Message (Get-UiText "Tab.ChangePassword")
        }
    }
    finally {
        $btnChange.Enabled = $true
    }
})


$btnGetAccountProps.Add_Click({
    $domain = $txtDomain.Text.Trim()
    $login = $txtLogin.Text.Trim()

    if ((Is-Blank $domain) -or (Is-Blank $login)) {
        Set-Status (Get-UiText "Status.EnterAccount") "Error"
        return
    }

    try {
        $btnGetAccountProps.Enabled = $false
        Set-Status (Get-UiText "Status.GettingAccountProperties" @($domain, $login)) "Info"
        $script:AccountPropertyRows = @(Get-AdUserAllPropertiesNoRsat -DomainOrDc $domain -Login $login)
        Set-AccountPropertiesGrid -Rows $script:AccountPropertyRows
        Set-Status (Get-UiText "Status.AccountPropertiesReceived" @(@($script:AccountPropertyRows).Count)) "Ok"
    }
    catch {
        $script:AccountPropertyRows = @()
        Set-AccountPropertiesGrid -Rows $script:AccountPropertyRows
        $msg = $_.Exception.Message
        Set-Status (Get-UiText "Status.AccountPropertiesError" @($msg)) "Error"
        Show-ErrorBox $msg (Get-UiText "Tab.AccountProperties")
    }
    finally {
        $btnGetAccountProps.Enabled = $true
    }
})

$btnClearAccountProps.Add_Click({
    $script:AccountPropertyRows = @()
    Set-AccountPropertiesGrid -Rows $script:AccountPropertyRows
    Set-Status (Get-UiText "Status.AccountPropertiesCleared") "Info"
})

$btnCopyAccountProps.Add_Click({
    try {
        $rows = @(Get-SelectedAccountPropertyRows)
        if ($rows.Count -eq 0) {
            Set-Status (Get-UiText "Status.SelectProperties") "Warn"
            return
        }
        [System.Windows.Forms.Clipboard]::SetText((Convert-AccountPropertyRowsToClipboardText -Rows $rows))
        Set-Status (Get-UiText "Status.PropertiesCopied" @($rows.Count)) "Ok"
    }
    catch {
        Set-Status (Get-UiText "Status.PropertiesCopyFailed" @($_.Exception.Message)) "Error"
    }
})

$btnCopyAllAccountProps.Add_Click({
    try {
        $rows = @($script:AccountPropertyRows)
        if ($rows.Count -eq 0) {
            Set-Status (Get-UiText "Status.NoProperties") "Warn"
            return
        }
        [System.Windows.Forms.Clipboard]::SetText((Convert-AccountPropertyRowsToClipboardText -Rows $rows))
        Set-Status (Get-UiText "Status.AllPropertiesCopied" @($rows.Count)) "Ok"
    }
    catch {
        Set-Status (Get-UiText "Status.PropertiesCopyFailed" @($_.Exception.Message)) "Error"
    }
})

$btnGetAccountGroups.Add_Click({
    $domain = $txtDomain.Text.Trim()
    $login = $txtLogin.Text.Trim()

    if ((Is-Blank $domain) -or (Is-Blank $login)) {
        Set-Status (Get-UiText "Status.EnterAccount") "Error"
        return
    }

    $progressWindow = $null

    try {
        $btnGetAccountGroups.Enabled = $false
        Set-Status (Get-UiText "Status.GettingAccountGroups" @($domain, $login)) "Info"
        $progressWindow = Show-BusyProgressWindow `
            -Title (Get-UiText "Tab.AccountGroups") `
            -Message (Get-UiText "Status.GettingAccountGroups" @($domain, $login)) `
            -Detail "$domain\$login"

        $script:AccountGroupRows = @(Get-AdAccountGroupsNoRsat -DomainOrDc $domain -Login $login -ProgressWindow $progressWindow)
        Set-AccountGroupsGrid -Rows $script:AccountGroupRows

        if (@($script:AccountGroupRows).Count -eq 0) {
            Set-Status (Get-UiText "Status.NoAccountGroups" @($domain, $login)) "Warn"
        }
        else {
            Set-Status (Get-UiText "Status.AccountGroupsReceived" @(@($script:AccountGroupRows).Count)) "Ok"
        }
    }
    catch {
        $script:AccountGroupRows = @()
        Set-AccountGroupsGrid -Rows $script:AccountGroupRows
        $msg = $_.Exception.Message
        Set-Status (Get-UiText "Status.AccountGroupsError" @($msg)) "Error"
        Close-BusyProgressWindow $progressWindow
        $progressWindow = $null
        Show-ErrorBox $msg (Get-UiText "Tab.AccountGroups")
    }
    finally {
        Close-BusyProgressWindow $progressWindow
        $btnGetAccountGroups.Enabled = $true
    }
})

$btnClearAccountGroups.Add_Click({
    $script:AccountGroupRows = @()
    Set-AccountGroupsGrid -Rows $script:AccountGroupRows
    Set-Status (Get-UiText "Status.AccountGroupsCleared") "Info"
})

$btnCopyAccountGroups.Add_Click({
    try {
        $rows = @(Get-SelectedAccountGroupRows)
        if ($rows.Count -eq 0) {
            Set-Status (Get-UiText "Status.SelectGroups") "Warn"
            return
        }
        [System.Windows.Forms.Clipboard]::SetText((Convert-AccountGroupRowsToClipboardText -Rows $rows))
        Set-Status (Get-UiText "Status.GroupsCopied" @($rows.Count)) "Ok"
    }
    catch {
        Set-Status (Get-UiText "Status.GroupsCopyFailed" @($_.Exception.Message)) "Error"
    }
})

$btnCopyAllAccountGroups.Add_Click({
    try {
        $rows = @($script:AccountGroupRows)
        if ($rows.Count -eq 0) {
            Set-Status (Get-UiText "Status.NoAccountGroupsToCopy") "Warn"
            return
        }
        [System.Windows.Forms.Clipboard]::SetText((Convert-AccountGroupRowsToClipboardText -Rows $rows))
        Set-Status (Get-UiText "Status.AllGroupsCopied" @($rows.Count)) "Ok"
    }
    catch {
        Set-Status (Get-UiText "Status.GroupsCopyFailed" @($_.Exception.Message)) "Error"
    }
})



$btnGetGroupMembers.Add_Click({
    $domain = $txtDomain.Text.Trim()
    $groupIdentity = $txtGroupMembersGroup.Text.Trim()

    if (Is-Blank $domain) {
        Set-Status (Get-UiText "Status.EnterDomain") "Error"
        return
    }

    if (Is-Blank $groupIdentity) {
        Set-Status (Get-UiText "Status.EnterGroup") "Error"
        return
    }

    $progressWindow = $null

    try {
        $btnGetGroupMembers.Enabled = $false
        Set-Status (Get-UiText "Status.GettingGroupMembers" @($domain, $groupIdentity)) "Info"
        $progressWindow = Show-BusyProgressWindow `
            -Title (Get-UiText "Tab.GroupMembers") `
            -Message (Get-UiText "Status.GettingGroupMembers" @($domain, $groupIdentity)) `
            -Detail "$domain\$groupIdentity"

        $script:DomainGroupMemberRows = @(Get-AdDomainGroupMembersNoRsat -DomainOrDc $domain -GroupIdentity $groupIdentity -ProgressWindow $progressWindow)
        Set-DomainGroupMembersGrid -Rows $script:DomainGroupMemberRows

        if (@($script:DomainGroupMemberRows).Count -eq 0) {
            Set-Status (Get-UiText "Status.NoGroupMembers" @($domain, $groupIdentity)) "Warn"
        }
        else {
            Set-Status (Get-UiText "Status.GroupMembersReceived" @(@($script:DomainGroupMemberRows).Count)) "Ok"
        }
    }
    catch {
        $script:DomainGroupMemberRows = @()
        Set-DomainGroupMembersGrid -Rows $script:DomainGroupMemberRows
        $msg = $_.Exception.Message
        Set-Status (Get-UiText "Status.GroupMembersError" @($msg)) "Error"
        Close-BusyProgressWindow $progressWindow
        $progressWindow = $null
        Show-ErrorBox $msg (Get-UiText "Tab.GroupMembers")
    }
    finally {
        Close-BusyProgressWindow $progressWindow
        $btnGetGroupMembers.Enabled = $true
    }
})

$btnClearGroupMembers.Add_Click({
    $script:DomainGroupMemberRows = @()
    Set-DomainGroupMembersGrid -Rows $script:DomainGroupMemberRows
    Set-Status (Get-UiText "Status.GroupMembersCleared") "Info"
})

$btnCopyGroupMembers.Add_Click({
    try {
        $rows = @(Get-SelectedDomainGroupMemberRows)
        if ($rows.Count -eq 0) {
            Set-Status (Get-UiText "Status.SelectGroupMembers") "Warn"
            return
        }
        [System.Windows.Forms.Clipboard]::SetText((Convert-DomainGroupMemberRowsToClipboardText -Rows $rows))
        Set-Status (Get-UiText "Status.GroupMembersCopied" @($rows.Count)) "Ok"
    }
    catch {
        Set-Status (Get-UiText "Status.GroupMembersCopyFailed" @($_.Exception.Message)) "Error"
    }
})

$btnCopyAllGroupMembers.Add_Click({
    try {
        $rows = @($script:DomainGroupMemberRows)
        if ($rows.Count -eq 0) {
            Set-Status (Get-UiText "Status.NoGroupMembersToCopy") "Warn"
            return
        }
        [System.Windows.Forms.Clipboard]::SetText((Convert-DomainGroupMemberRowsToClipboardText -Rows $rows))
        Set-Status (Get-UiText "Status.AllGroupMembersCopied" @($rows.Count)) "Ok"
    }
    catch {
        Set-Status (Get-UiText "Status.GroupMembersCopyFailed" @($_.Exception.Message)) "Error"
    }
})



$btnGetManagedGroups.Add_Click({
    $domain = $txtDomain.Text.Trim()
    $login = $txtLogin.Text.Trim()

    if ((Is-Blank $domain) -or (Is-Blank $login)) {
        Set-Status (Get-UiText "Status.EnterManager") "Error"
        return
    }

    $progressWindow = $null

    try {
        $btnGetManagedGroups.Enabled = $false
        Set-Status (Get-UiText "Status.GettingManagedGroups" @($domain, $login)) "Info"
        $progressWindow = Show-BusyProgressWindow `
            -Title (Get-UiText "Tab.ManagedGroups") `
            -Message (Get-UiText "Status.GettingManagedGroups" @($domain, $login)) `
            -Detail "$domain\$login"

        $script:ManagedGroupRows = @(Get-ManagedGroups -DomainOrDc $domain -ManagerLogin $login -ProgressWindow $progressWindow)
        Set-ManagedGroupsGrid -Rows $script:ManagedGroupRows

        if (@($script:ManagedGroupRows).Count -eq 0) {
            Set-Status (Get-UiText "Status.NoManagedGroups" @($domain, $login)) "Warn"
        }
        else {
            Set-Status (Get-UiText "Status.ManagedGroupsReceived" @(@($script:ManagedGroupRows).Count)) "Ok"
        }
    }
    catch {
        $script:ManagedGroupRows = @()
        Set-ManagedGroupsGrid -Rows $script:ManagedGroupRows
        $msg = $_.Exception.Message
        Set-Status (Get-UiText "Status.ManagedGroupsError" @($msg)) "Error"
        Close-BusyProgressWindow $progressWindow
        $progressWindow = $null
        Show-ErrorBox $msg (Get-UiText "Tab.ManagedGroups")
    }
    finally {
        Close-BusyProgressWindow $progressWindow
        $btnGetManagedGroups.Enabled = $true
    }
})

$btnClearManagedGroups.Add_Click({
    $script:ManagedGroupRows = @()
    Set-ManagedGroupsGrid -Rows $script:ManagedGroupRows
    Set-Status (Get-UiText "Status.ManagedGroupsCleared") "Info"
})

$btnCopyManagedGroups.Add_Click({
    try {
        $rows = @(Get-SelectedManagedGroupRows)
        if ($rows.Count -eq 0) {
            Set-Status (Get-UiText "Status.SelectManagedGroups") "Warn"
            return
        }
        [System.Windows.Forms.Clipboard]::SetText((Convert-AccountGroupRowsToClipboardText -Rows $rows))
        Set-Status (Get-UiText "Status.ManagedGroupsCopied" @($rows.Count)) "Ok"
    }
    catch {
        Set-Status (Get-UiText "Status.ManagedGroupsCopyFailed" @($_.Exception.Message)) "Error"
    }
})

$btnCopyAllManagedGroups.Add_Click({
    try {
        $rows = @($script:ManagedGroupRows)
        if ($rows.Count -eq 0) {
            Set-Status (Get-UiText "Status.NoManagedGroupsToCopy") "Warn"
            return
        }
        [System.Windows.Forms.Clipboard]::SetText((Convert-AccountGroupRowsToClipboardText -Rows $rows))
        Set-Status (Get-UiText "Status.AllManagedGroupsCopied" @($rows.Count)) "Ok"
    }
    catch {
        Set-Status (Get-UiText "Status.ManagedGroupsCopyFailed" @($_.Exception.Message)) "Error"
    }
})


$btnManaged.Add_Click({
    $domain = $txtDomain.Text.Trim()
    $login = $txtLogin.Text.Trim()

    if ((Is-Blank $domain) -or (Is-Blank $login)) {
        Set-Status (Get-UiText "Status.EnterManager") "Error"
        return
    }

    try {
        $btnManaged.Enabled = $false
        Set-Status (Get-UiText "Status.FindingManagerAccounts" @($domain, $login)) "Info"
        $script:ManagedRowsAll = @(Get-ManagedAccounts -DomainOrDc $domain -ManagerLogin $login)
        $script:ManagedRowsLoaded = $true

        $visibleCount = Refresh-ManagedAccountsGrid
        $totalCount = @($script:ManagedRowsAll).Count
        $filterText = Get-ManagedAccountsFilterText

        if ($totalCount -eq 0) {
            Set-Status (Get-UiText "Status.NoManagerAccounts" @($domain, $login)) "Warn"
        }
        else {
            Set-Status (Get-UiText "Status.ManagerAccountsReceived" @($totalCount, $visibleCount, $filterText)) "Ok"
        }
    }
    catch {
        $script:ManagedRowsAll = @()
        $script:ManagedRowsLoaded = $false
$script:AccountPropertyRows = @()
        $gridManaged.Rows.Clear()
        $lblManagedCount.Text = Get-UiText "ManagerAccounts.CountEmpty"
        $msg = $_.Exception.Message
        Set-Status (Get-UiText "Status.ManagerAccountsError" @($msg)) "Error"
        Show-ErrorBox $msg (Get-UiText "Tab.ManagerAccounts")
    }
    finally {
        $btnManaged.Enabled = $true
    }
})

$btnClearManaged.Add_Click({
    $script:ManagedRowsAll = @()
    $script:ManagedRowsLoaded = $false
$script:AccountPropertyRows = @()
    $gridManaged.Rows.Clear()
    $gridManaged.ClearSelection()
    $txtManagedSearch.Clear()
    $rdoManagedAll.Checked = $true
    $lblManagedCount.Text = Get-UiText "ManagerAccounts.CountEmpty"
    Set-Status (Get-UiText "Status.ManagerAccountsCleared") "Info"
})

$btnExportCsv.Add_Click({ Export-ManagedAccountsWithDialog -Format "CSV" })
$btnExportXlsx.Add_Click({ Export-ManagedAccountsWithDialog -Format "XLSX" })
$btnCopyLogins.Add_Click({ Copy-SelectedLoginsToClipboard })

$rdoManagedAll.Add_CheckedChanged({ if ($rdoManagedAll.Checked) { Update-ManagedAccountsFilterView } })
$rdoManagedActive.Add_CheckedChanged({ if ($rdoManagedActive.Checked) { Update-ManagedAccountsFilterView } })
$rdoManagedInactive.Add_CheckedChanged({ if ($rdoManagedInactive.Checked) { Update-ManagedAccountsFilterView } })
$txtManagedSearch.Add_TextChanged({ Update-ManagedAccountsFilterView })

$form.Add_KeyDown({
    param($sender, $e)
    if ($e.Control -and $e.KeyCode -eq [System.Windows.Forms.Keys]::L) {
        try { if ($null -ne $txtLogMain) { $txtLogMain.Clear() } } catch { }
        $e.Handled = $true
    }
})

$form.Add_Shown({
    Set-Status (Get-UiText "Status.Ready") "Info"
    try { $txtLogin.Focus() } catch { }
})

$form.Add_FormClosed({
    try {
        foreach ($ctrl in @($form, $header, $contextPanel, $tabs, $txtLogMain, $gridManaged, $gridAccountProps, $gridAccountGroups)) {
            if ($null -ne $ctrl) { $ctrl.Dispose() }
        }
        if ($null -ne $script:BrandImage) {
            $script:BrandImage.Dispose()
            $script:BrandImage = $null
        }
        if ($null -ne $script:BrandImageStream) {
            $script:BrandImageStream.Dispose()
            $script:BrandImageStream = $null
        }
    }
    catch { }
})

[void]$form.ShowDialog()
