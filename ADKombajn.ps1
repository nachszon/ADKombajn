#requires -Version 5.1
# Build: 2.13.1-public
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

$script:AppName = "AD Kombajn"
$script:AppVersion = "2.13.1"
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
        "Header.Subtitle" = "Walidacja, zmiana hasła, właściwości konta, grupy konta, konta managera, log"
        "Header.Author" = "Autor: {0}"
        "Busy.Title" = "Przetwarzanie"
        "Busy.Message" = "Proszę czekać..."
        "Busy.Detail" = "Operacja jest wykonywana w Active Directory."
        "Busy.DoNotClose" = "Proszę nie zamykać aplikacji w trakcie operacji."
        "Error.GuiUnhandled" = "Nieobsłużony błąd interfejsu: {0}"
        "Error.AppTitle" = "Błąd AD Kombajna"
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
        "Error.ManagerNotFound" = "Nie znaleziono konta managera: {0}\{1}"
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
        "Progress.FindManager" = "Szukam konta managera"
        "Progress.FindManagedGroups" = "Szukam grup managera"
        "Progress.OrganizeManagedGroups" = "Porządkuję grupy managera"
        "Context.Title" = "Kontekst pracy"
        "Context.Domain" = "Domena / DC:"
        "Context.AccountLogin" = "Login konta:"
        "Context.Mode" = "Domyślnie: LDAP 389 + signing/sealing, bez RSAT."
        "Tab.ValidatePassword" = "Walidacja hasła"
        "Tab.ChangePassword" = "Zmiana hasła"
        "Tab.ManagerAccounts" = "Konta managera"
        "Tab.AccountProperties" = "Właściwości konta"
        "Tab.AccountGroups" = "Grupy konta"
        "Tab.GroupMembers" = "Członkowie grupy"
        "Tab.ManagedGroups" = "Grupy managera"
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
        "ManagedGroups.Info" = "Pokazuje grupy domenowe, których atrybut manager wskazuje konto z pola Login konta."
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
        "Export.SheetName" = "Konta managera"
        "Export.FileNameBase" = "konta_managera"
        "Export.NoDataPart" = "brak"
        "Export.SaveTitle" = "Zapisz konta managera"
        "Export.CsvFilter" = "CSV rozdzielany średnikiem (*.csv)|*.csv|Wszystkie pliki (*.*)|*.*"
        "Export.XlsxFilter" = "Excel Workbook (*.xlsx)|*.xlsx|Wszystkie pliki (*.*)|*.*"
        "Dialog.NoData" = "Brak danych"
        "Dialog.NoSelection" = "Brak zaznaczenia"
        "Status.Filter" = "Filtr: {0}, tekst: '{1}' - pokazano {2} z {3} kont."
        "Status.GetManagerAccountsFirst" = "Najpierw pobierz konta managera."
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
        "Status.EnterManager" = "Podaj domenę/DC i login managera."
        "Status.GettingManagedGroups" = "Pobieram grupy, gdzie managedBy wskazuje {0}\{1}..."
        "Status.NoManagedGroups" = "OK - nie znaleziono grup managedBy dla {0}\{1}."
        "Status.ManagedGroupsReceived" = "OK - znaleziono grup managera: {0}."
        "Status.ManagedGroupsError" = "Błąd pobierania grup managera: {0}"
        "Status.ManagedGroupsCleared" = "Lista grup managera wyczyszczona."
        "Status.SelectManagedGroups" = "Zaznacz grupy managera do skopiowania."
        "Status.ManagedGroupsCopied" = "Skopiowano zaznaczone grupy managera: {0}."
        "Status.ManagedGroupsCopyFailed" = "Nie udało się skopiować grup managera: {0}"
        "Status.NoManagedGroupsToCopy" = "Brak grup managera do skopiowania."
        "Status.AllManagedGroupsCopied" = "Skopiowano wszystkie grupy managera: {0}."
        "Status.FindingManagerAccounts" = "Szukam kont, gdzie managerem jest {0}\{1}..."
        "Status.NoManagerAccounts" = "OK - nie znaleziono kont dla managera {0}\{1}."
        "Status.ManagerAccountsReceived" = "OK - znaleziono kont: {0}; pokazano: {1} ({2})."
        "Status.ManagerAccountsError" = "Błąd pobierania kont managera: {0}"
        "Status.ManagerAccountsCleared" = "Lista kont managera wyczyszczona."
    }
    en = @{
        "App.WindowTitle" = "{0} {1} - no RSAT"
        "Splash.Subtitle" = "PASSWORDS  •  ACCOUNTS  •  GROUPS"
        "Splash.Author" = "Author: {0}"
        "Splash.Version" = "VERSION {0}"
        "Splash.Loading" = "Loading interface..."
        "Header.Subtitle" = "Password validation and change, account properties, groups, manager accounts, log"
        "Header.Author" = "Author: {0}"
        "Busy.Title" = "Processing"
        "Busy.Message" = "Please wait..."
        "Busy.Detail" = "The operation is being performed in Active Directory."
        "Busy.DoNotClose" = "Please do not close the application during the operation."
        "Error.GuiUnhandled" = "Unhandled interface error: {0}"
        "Error.AppTitle" = "AD Kombajn error"
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
        "Error.ManagerNotFound" = "Manager account not found: {0}\{1}"
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
        "Progress.FindManager" = "Searching for the manager account"
        "Progress.FindManagedGroups" = "Searching for managed groups"
        "Progress.OrganizeManagedGroups" = "Organizing managed groups"
        "Context.Title" = "Working context"
        "Context.Domain" = "Domain / DC:"
        "Context.AccountLogin" = "Account login:"
        "Context.Mode" = "Default: LDAP 389 + signing/sealing, no RSAT."
        "Tab.ValidatePassword" = "Validate password"
        "Tab.ChangePassword" = "Change password"
        "Tab.ManagerAccounts" = "Manager accounts"
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
        "ManagedGroups.Info" = "Displays domain groups whose manager attribute points to the account entered in Account login."
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
        "Export.SheetName" = "Manager accounts"
        "Export.FileNameBase" = "manager_accounts"
        "Export.NoDataPart" = "none"
        "Export.SaveTitle" = "Save manager accounts"
        "Export.CsvFilter" = "Semicolon-delimited CSV (*.csv)|*.csv|All files (*.*)|*.*"
        "Export.XlsxFilter" = "Excel Workbook (*.xlsx)|*.xlsx|All files (*.*)|*.*"
        "Dialog.NoData" = "No data"
        "Dialog.NoSelection" = "No selection"
        "Status.Filter" = "Filter: {0}, text: '{1}' - showing {2} of {3} accounts."
        "Status.GetManagerAccountsFirst" = "Retrieve the manager accounts first."
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
        "Status.EnterManager" = "Enter the domain/DC and manager login."
        "Status.GettingManagedGroups" = "Retrieving groups whose managedBy points to {0}\{1}..."
        "Status.NoManagedGroups" = "OK - no managedBy groups found for {0}\{1}."
        "Status.ManagedGroupsReceived" = "OK - managed groups found: {0}."
        "Status.ManagedGroupsError" = "Error retrieving managed groups: {0}"
        "Status.ManagedGroupsCleared" = "Managed group list cleared."
        "Status.SelectManagedGroups" = "Select managed groups to copy."
        "Status.ManagedGroupsCopied" = "Selected managed groups copied: {0}."
        "Status.ManagedGroupsCopyFailed" = "Could not copy managed groups: {0}"
        "Status.NoManagedGroupsToCopy" = "There are no managed groups to copy."
        "Status.AllManagedGroupsCopied" = "All managed groups copied: {0}."
        "Status.FindingManagerAccounts" = "Searching for accounts managed by {0}\{1}..."
        "Status.NoManagerAccounts" = "OK - no accounts found for manager {0}\{1}."
        "Status.ManagerAccountsReceived" = "OK - accounts found: {0}; shown: {1} ({2})."
        "Status.ManagerAccountsError" = "Error retrieving manager accounts: {0}"
        "Status.ManagerAccountsCleared" = "Manager account list cleared."
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
    Accent      = [System.Drawing.Color]::FromArgb(0, 120, 215)
    AccentDark  = [System.Drawing.Color]::FromArgb(0, 88, 165)
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
    $dialog.Text = "AD Kombajn - Language / Język"
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
    $btn.FlatAppearance.BorderSize = 0
    $btn.BackColor = $BackColor
    $btn.ForeColor = $ForeColor
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
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
        [string]$Title = "AD KOMBAJN",
        [string]$Subtitle = (Get-UiText "Splash.Subtitle"),
        [string]$Version = $script:AppVersion,
        [string]$Author = (Get-UiText "Splash.Author" @($script:AppAuthor))
    )

    try {
        $w = 580
        $h = 330
        $totalMs = [Math]::Max(700, [int]$Milliseconds)

        $splash = New-Object System.Windows.Forms.Form
        $splash.Width = $w
        $splash.Height = $h
        $splash.StartPosition = "CenterScreen"
        $splash.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
        $splash.ShowInTaskbar = $false
        $splash.TopMost = $true
        $splash.BackColor = $script:Theme.Navy
        $splash.Opacity = 0.0
        Set-DoubleBuffered $splash
        Apply-AppWindowIcon $splash

        $regionRect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
        $regionPath = New-RoundedRectanglePath -Rect $regionRect -Radius 30
        $splash.Region = New-Object System.Drawing.Region($regionPath)

        $bmp = New-Object System.Drawing.Bitmap($w, $h)
        $g = [System.Drawing.Graphics]::FromImage($bmp)

        $disposables = New-Object System.Collections.ArrayList
        try {
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

            $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
            $bgBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, [System.Drawing.Color]::FromArgb(5, 24, 63), [System.Drawing.Color]::FromArgb(0, 135, 245), 38.0)
            [void]$disposables.Add($bgBrush)
            $g.FillRectangle($bgBrush, $rect)

            $shine = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(45, 255, 255, 255))
            [void]$disposables.Add($shine)
            $g.FillEllipse($shine, -120, -135, 430, 260)
            $g.FillEllipse($shine, 420, 205, 210, 150)

            $darkRect = New-Object System.Drawing.Rectangle(0, 205, $w, 125)
            $darkBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($darkRect, [System.Drawing.Color]::FromArgb(8, 16, 35), [System.Drawing.Color]::FromArgb(100, 0, 0, 0), 90.0)
            [void]$disposables.Add($darkBrush)
            $g.FillRectangle($darkBrush, $darkRect)

            $borderPath = New-RoundedRectanglePath -Rect (New-Object System.Drawing.Rectangle(1, 1, ($w - 3), ($h - 3))) -Radius 30
            [void]$disposables.Add($borderPath)
            $borderPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(150, 220, 245, 255), 1)
            [void]$disposables.Add($borderPen)
            $g.DrawPath($borderPen, $borderPath)

            # Icon: magnifying glass + database, drawn without external files.
            $shadowBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(75, 0, 0, 0))
            [void]$disposables.Add($shadowBrush)
            $g.FillEllipse($shadowBrush, 57, 205, 160, 26)

            $dbRect = New-Object System.Drawing.Rectangle(50, 154, 115, 62)
            $dbBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($dbRect, [System.Drawing.Color]::FromArgb(250, 255, 255, 255), [System.Drawing.Color]::FromArgb(130, 145, 165), 0.0)
            [void]$disposables.Add($dbBrush)
            $dbBlue = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0, 125, 255))
            [void]$disposables.Add($dbBlue)
            $dbPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(230, 245, 250, 255), 2)
            [void]$disposables.Add($dbPen)

            $g.FillRectangle($dbBrush, 55, 168, 105, 42)
            $g.FillEllipse($dbBrush, 55, 153, 105, 30)
            $g.DrawEllipse($dbPen, 55, 153, 105, 30)
            $g.FillRectangle($dbBlue, 56, 179, 103, 8)
            $g.DrawArc($dbPen, 55, 175, 105, 28, 0, 180)
            $g.DrawArc($dbPen, 55, 194, 105, 24, 0, 180)

            $handleOuter = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(235, 242, 245, 250), 16)
            [void]$disposables.Add($handleOuter)
            $handleOuter.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
            $handleOuter.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
            $handleInner = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(0, 90, 205), 9)
            [void]$disposables.Add($handleInner)
            $handleInner.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
            $handleInner.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
            $lensOuter = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(245, 250, 252, 255), 13)
            [void]$disposables.Add($lensOuter)
            $lensInner = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(0, 165, 255), 4)
            [void]$disposables.Add($lensInner)
            $glassRect = New-Object System.Drawing.Rectangle(78, 76, 105, 105)
            $glassBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($glassRect, [System.Drawing.Color]::FromArgb(220, 220, 250, 255), [System.Drawing.Color]::FromArgb(170, 0, 105, 235), 45.0)
            [void]$disposables.Add($glassBrush)

            $g.DrawLine($handleOuter, 158, 162, 206, 210)
            $g.DrawLine($handleInner, 166, 170, 207, 210)
            $g.FillEllipse($glassBrush, 78, 76, 105, 105)
            $g.DrawEllipse($lensOuter, 78, 76, 105, 105)
            $g.DrawEllipse($lensInner, 86, 84, 89, 89)

            $highlight = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(120, 255, 255, 255))
            [void]$disposables.Add($highlight)
            $g.FillEllipse($highlight, 101, 92, 45, 22)

            $titleFont = New-Object System.Drawing.Font("Segoe UI", 30, [System.Drawing.FontStyle]::Bold)
            [void]$disposables.Add($titleFont)
            $subtitleFont = New-Object System.Drawing.Font("Segoe UI Semibold", 10, [System.Drawing.FontStyle]::Regular)
            [void]$disposables.Add($subtitleFont)
            $versionFont = New-Object System.Drawing.Font("Segoe UI Semibold", 9, [System.Drawing.FontStyle]::Regular)
            [void]$disposables.Add($versionFont)
            $smallFont = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular)
            [void]$disposables.Add($smallFont)
            $authorFont = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
            [void]$disposables.Add($authorFont)
            $versionFont = New-Object System.Drawing.Font("Segoe UI Semibold", 9, [System.Drawing.FontStyle]::Regular)
            [void]$disposables.Add($versionFont)

            $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
            [void]$disposables.Add($white)
            $shadow = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(95, 0, 0, 0))
            [void]$disposables.Add($shadow)
            $soft = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(205, 235, 255))
            [void]$disposables.Add($soft)
            $muted = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(165, 210, 235, 255))
            [void]$disposables.Add($muted)

            $sfNear = New-Object System.Drawing.StringFormat
            [void]$disposables.Add($sfNear)
            $sfNear.Alignment = [System.Drawing.StringAlignment]::Near
            $sfNear.LineAlignment = [System.Drawing.StringAlignment]::Center
            $sfCenter = New-Object System.Drawing.StringFormat
            [void]$disposables.Add($sfCenter)
            $sfCenter.Alignment = [System.Drawing.StringAlignment]::Center
            $sfCenter.LineAlignment = [System.Drawing.StringAlignment]::Center

            $g.DrawString($Title, $titleFont, $shadow, (New-Object System.Drawing.RectangleF(226, 99, 325, 50)), $sfNear)
            $g.DrawString($Title, $titleFont, $white,  (New-Object System.Drawing.RectangleF(223, 96, 325, 50)), $sfNear)
            $g.DrawString($Subtitle, $subtitleFont, $soft, (New-Object System.Drawing.RectangleF(229, 151, 320, 24)), $sfNear)
            $g.DrawString((Get-UiText "Splash.Version" @($Version)), $versionFont, $muted, (New-Object System.Drawing.RectangleF(229, 177, 320, 20)), $sfNear)
            $g.DrawString((Get-UiText "Splash.Loading"), $smallFont, $soft, (New-Object System.Drawing.RectangleF(56, 254, 468, 20)), $sfCenter)
            $g.DrawString($Author, $authorFont, $muted, (New-Object System.Drawing.RectangleF(56, 301, 468, 18)), $sfCenter)
        }
        finally {
            for ($i = $disposables.Count - 1; $i -ge 0; $i--) {
                try { $disposables[$i].Dispose() } catch { }
            }
            if ($null -ne $g) { $g.Dispose() }
        }

        $picture = New-Object System.Windows.Forms.PictureBox
        $picture.Dock = [System.Windows.Forms.DockStyle]::Fill
        $picture.Image = $bmp
        $picture.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Normal

        $barBack = New-Object System.Windows.Forms.Panel
        $barBack.Location = New-Point 56 282
        $barBack.Size = New-Size 468 8
        $barBack.BackColor = [System.Drawing.Color]::FromArgb(25, 60, 105)

        $barFill = New-Object System.Windows.Forms.Panel
        $barFill.Location = New-Point 0 0
        $barFill.Size = New-Size 12 8
        $barFill.BackColor = [System.Drawing.Color]::FromArgb(0, 195, 255)
        [void]$barBack.Controls.Add($barFill)

        [void]$splash.Controls.Add($picture)
        [void]$splash.Controls.Add($barBack)
        $barBack.BringToFront()

        $splash.Show()
        [System.Windows.Forms.Application]::DoEvents()

        $step = 25
        $elapsed = 0
        while ($elapsed -lt $totalMs) {
            $progress = [Math]::Min(1.0, ([double]$elapsed / [double]$totalMs))
            $barFill.Width = [int]([Math]::Max(12.0, [double]$barBack.Width * $progress))

            if ($elapsed -lt 250) {
                $splash.Opacity = [Math]::Min(0.98, ([double]$elapsed / 250.0))
            }
            elseif ($elapsed -gt ($totalMs - 280)) {
                $remaining = [Math]::Max(0, ($totalMs - $elapsed))
                $splash.Opacity = [Math]::Max(0.0, ([double]$remaining / 280.0))
            }
            else {
                $splash.Opacity = 0.98
            }

            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds $step
            $elapsed += $step
        }

        $splash.Close()
        [System.Windows.Forms.Application]::DoEvents()

        if ($null -ne $bmp) { $bmp.Dispose() }
        if ($null -ne $regionPath) { $regionPath.Dispose() }
        if ($null -ne $splash) { $splash.Dispose() }
    }
    catch {
        try { if ($null -ne $splash) { $splash.Dispose() } } catch { }
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
  <dc:creator>AD Kombajn</dc:creator>
  <cp:lastModifiedBy>AD Kombajn</cp:lastModifiedBy>
  <dcterms:created xsi:type="dcterms:W3CDTF">$nowUtc</dcterms:created>
  <dcterms:modified xsi:type="dcterms:W3CDTF">$nowUtc</dcterms:modified>
</cp:coreProperties>
"@

        Write-Utf8NoBomFile -Path (Join-Path $tmp "docProps\app.xml") -Content @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
  <Application>AD Kombajn</Application>
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
Show-WinSplash -Milliseconds 1600 -Title "AD KOMBAJN" -Subtitle (Get-UiText "Splash.Subtitle") -Version $script:AppVersion -Author (Get-UiText "Splash.Author" @($script:AppAuthor))

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
$header.Height = 92
$header.BackColor = $script:Theme.Navy
Set-DoubleBuffered $header
$header.Add_Paint({
    param($sender, $e)

    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    $rect = New-Object System.Drawing.Rectangle(0, 0, $sender.Width, $sender.Height)
    $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, [System.Drawing.Color]::FromArgb(7, 29, 73), [System.Drawing.Color]::FromArgb(0, 125, 230), 25.0)
    $g.FillRectangle($bg, $rect)
    $bg.Dispose()

    $shine = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(35, 255, 255, 255))
    $g.FillEllipse($shine, -80, -120, 360, 180)
    $shine.Dispose()

    $penOuter = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(225, 245, 250, 255), 5)
    $penInner = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(0, 180, 255), 2)
    $handle = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(225, 245, 250, 255), 7)
    $handle.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $handle.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawLine($handle, 54, 52, 72, 70)
    $g.DrawEllipse($penOuter, 28, 22, 34, 34)
    $g.DrawEllipse($penInner, 32, 26, 26, 26)
    $penOuter.Dispose(); $penInner.Dispose(); $handle.Dispose()

    $titleFont = New-Object System.Drawing.Font("Segoe UI", 22, [System.Drawing.FontStyle]::Bold)
    $subFont = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Regular)
    $authorFont = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Italic)
    $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $soft = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(210, 232, 248, 255))
    $muted = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(170, 225, 240, 255))
    $g.DrawString("AD Kombajn", $titleFont, $white, 88, 18)
    $g.DrawString((Get-UiText "Header.Subtitle"), $subFont, $soft, 91, 55)
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
$btnExit.BackColor = [System.Drawing.Color]::FromArgb(25, 72, 128)
$btnExit.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnExit.FlatAppearance.BorderSize = 1
$btnExit.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(190, 235, 248, 255)
$btnExit.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(38, 96, 158)
$btnExit.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(10, 47, 92)
$btnExit.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnExit.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$btnExit.UseVisualStyleBackColor = $false
$btnExit.TabStop = $false
$btnExit.AccessibleName = Get-UiText "Common.Exit"

$positionExitButton = {
    $x = [Math]::Max(0, $header.ClientSize.Width - $btnExit.Width - 22)
    $btnExit.Location = New-Point $x 16
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
    }
    catch { }
})

[void]$form.ShowDialog()
