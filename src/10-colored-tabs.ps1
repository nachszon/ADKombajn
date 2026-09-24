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

