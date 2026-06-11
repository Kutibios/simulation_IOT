import sqlite3
import pandas as pd
from dash import Dash, html, dcc, callback, Output, Input, State
import plotly.graph_objects as go
from datetime import datetime, timezone, timedelta

TZ_TR = timezone(timedelta(hours=3))

DB_PATH = "/data/telemetry.db"

SENSORS = [
    ("sicaklik", "Sıcaklık", "°C",  "#e74c3c", "rgba(231,76,60,0.1)"),
    ("nem",      "Nem",      "%",   "#3498db", "rgba(52,152,219,0.1)"),
    ("isik",     "Işık",     "lx",  "#f39c12", "rgba(243,156,18,0.1)"),
]

G_BG     = "#111827"
G_PANEL  = "#1f2937"
G_BORDER = "#374151"
G_TEXT   = "#e5e7eb"
G_MUTED  = "#9ca3af"
G_GREEN  = "#22c55e"

app = Dash(__name__)

app.index_string = """
<!DOCTYPE html><html>
<head>
    <title>IoT Sensör Paneli</title>
    {%metas%}{%favicon%}{%css%}
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { font-family: "Inter","Segoe UI",Arial,sans-serif; }
        @keyframes pulse { 0%,100%{opacity:1} 50%{opacity:.4} }
    </style>
</head>
<body>{%app_entry%}{%config%}{%scripts%}{%renderer%}</body>
</html>
"""

# ── Layout ────────────────────────────────────────────────────────────────────

app.layout = html.Div(id="root", children=[
    dcc.Store(id="theme-store", data="classic"),
    dcc.Interval(id="interval", interval=5000, n_intervals=0),

    # Butonlar her zaman DOM'da sabit
    html.Div(
        id="nav-bar",
        style={"display": "flex", "gap": "10px", "padding": "16px 20px 0"},
        children=[
            html.Button("Klasik",  id="btn-classic", n_clicks=0,
                        style={"padding": "8px 20px", "borderRadius": "6px", "cursor": "pointer",
                               "fontWeight": "600", "fontSize": "13px", "border": "1px solid #d1d5db",
                               "backgroundColor": "#e5e7eb", "color": "#111827"}),
            html.Button("Grafana", id="btn-grafana", n_clicks=0,
                        style={"padding": "8px 20px", "borderRadius": "6px", "cursor": "pointer",
                               "fontWeight": "600", "fontSize": "13px", "border": "1px solid #374151",
                               "backgroundColor": "transparent", "color": "#9ca3af"}),
        ],
    ),

    html.Div(id="page-content"),
])

# ── Theme switch ──────────────────────────────────────────────────────────────

@callback(
    Output("theme-store", "data"),
    Output("btn-classic", "style"),
    Output("btn-grafana", "style"),
    Input("btn-classic", "n_clicks"),
    Input("btn-grafana", "n_clicks"),
    prevent_initial_call=True,
)
def switch_theme(n_classic, n_grafana):
    from dash import ctx
    theme = "grafana" if ctx.triggered_id == "btn-grafana" else "classic"
    classic_style = {
        "padding": "8px 20px", "borderRadius": "6px", "cursor": "pointer",
        "fontWeight": "600", "fontSize": "13px",
        "border": "1px solid #d1d5db" if theme == "classic" else "1px solid #374151",
        "backgroundColor": "#e5e7eb" if theme == "classic" else "transparent",
        "color": "#111827" if theme == "classic" else "#9ca3af",
    }
    grafana_style = {
        "padding": "8px 20px", "borderRadius": "6px", "cursor": "pointer",
        "fontWeight": "600", "fontSize": "13px",
        "border": "1px solid #e95f2b" if theme == "grafana" else "1px solid #374151",
        "backgroundColor": "#e95f2b" if theme == "grafana" else "transparent",
        "color": "white" if theme == "grafana" else "#9ca3af",
    }
    return theme, classic_style, grafana_style

# ── Render ────────────────────────────────────────────────────────────────────

@callback(
    Output("page-content", "children"),
    Output("root", "style"),
    Input("interval", "n_intervals"),
    Input("theme-store", "data"),
)
def render(_, theme):
    try:
        conn = sqlite3.connect(DB_PATH)
        df = pd.read_sql("SELECT * FROM telemetry ORDER BY id", conn)
        conn.close()
        df["timestamp"] = pd.to_datetime(df["timestamp"], utc=True).dt.tz_convert(TZ_TR).dt.tz_localize(None)
    except Exception:
        df = None

    if theme == "grafana":
        root_style = {"backgroundColor": G_BG, "minHeight": "100vh"}
        return grafana_page(df), root_style
    else:
        root_style = {"backgroundColor": "#f5f5f5", "minHeight": "100vh"}
        return classic_page(df), root_style

# ── Klasik sayfa ──────────────────────────────────────────────────────────────

def classic_page(df):
    def stat_box(label, value, unit):
        return html.Div(f"{label}: {value:.2f} {unit}", style={"margin": "4px 0", "fontSize": "14px"})

    def make_row(df, col, label, unit, color):
        series = df[col].dropna()
        if series.empty:
            return html.Div(f"{label}: veri yok")
        fig = go.Figure()
        fig.add_trace(go.Scatter(x=df["timestamp"], y=df[col], mode="lines",
                                 line=dict(color=color, width=2), name=label))
        fig.update_layout(margin=dict(l=10, r=10, t=10, b=10),
                          paper_bgcolor="white", plot_bgcolor="white", height=200,
                          xaxis=dict(showgrid=False),
                          yaxis=dict(title=unit, showgrid=True, gridcolor="#eee"),
                          showlegend=False)
        stats = html.Div(
            style={"display": "flex", "flexDirection": "column", "justifyContent": "center",
                   "padding": "0 20px", "minWidth": "160px"},
            children=[html.B(label, style={"marginBottom": "8px", "fontSize": "15px"}),
                      stat_box("Min", series.min(), unit), stat_box("Max", series.max(), unit),
                      stat_box("Ort", series.mean(), unit), stat_box("Var", series.var(), unit + "²")])
        return html.Div(
            style={"display": "flex", "alignItems": "center", "backgroundColor": "white",
                   "borderRadius": "10px", "boxShadow": "0 2px 6px rgba(0,0,0,.1)",
                   "marginBottom": "20px", "padding": "15px"},
            children=[dcc.Graph(figure=fig, style={"flex": "1"}), stats])

    if df is None or df.empty:
        body = html.Div("Henüz veri yok...", style={"color": "#888"})
    else:
        body = [make_row(df, col, label, unit, color) for col, label, unit, color, _ in SENSORS]

    return html.Div(style={"padding": "20px"},
                    children=[html.H2("IoT Sensör Paneli — Takım 7",
                                      style={"textAlign": "center", "marginBottom": "30px"}),
                               html.Div(body)])

# ── Grafana temalı sayfa ──────────────────────────────────────────────────────

def grafana_page(df):
    def g_stat(label, value, unit):
        return html.Div(style={"marginBottom": "12px"}, children=[
            html.Div(label, style={"fontSize": "11px", "color": G_MUTED,
                                   "textTransform": "uppercase", "letterSpacing": "0.05em", "marginBottom": "2px"}),
            html.Div(f"{value:.2f} {unit}", style={"fontSize": "20px", "fontWeight": "600", "color": G_TEXT}),
        ])

    def make_row(df, col, label, unit, color, fill):
        series = df[col].dropna()
        if series.empty:
            return html.Div(f"{label}: veri yok", style={"color": G_MUTED})
        fig = go.Figure()
        fig.add_trace(go.Scatter(x=df["timestamp"], y=df[col], mode="lines",
                                 line=dict(color=color, width=2), fill="tozeroy",
                                 fillcolor=fill, name=label,
                                 hovertemplate=f"<b>%{{y:.2f}} {unit}</b><br>%{{x}}<extra></extra>"))
        fig.update_layout(margin=dict(l=10, r=10, t=10, b=10),
                          paper_bgcolor=G_PANEL, plot_bgcolor=G_PANEL, height=180,
                          xaxis=dict(showgrid=True, gridcolor=G_BORDER, color=G_MUTED,
                                     tickfont=dict(size=11), zeroline=False),
                          yaxis=dict(title=unit, color=G_MUTED, tickfont=dict(size=11),
                                     showgrid=True, gridcolor=G_BORDER, zeroline=False),
                          showlegend=False,
                          hoverlabel=dict(bgcolor=G_BORDER, font_color=G_TEXT))
        stats_panel = html.Div(
            style={"width": "180px", "flexShrink": "0", "borderLeft": f"1px solid {G_BORDER}",
                   "padding": "16px 20px", "display": "flex", "flexDirection": "column", "justifyContent": "center"},
            children=[
                html.Div(style={"display": "flex", "alignItems": "center", "gap": "8px", "marginBottom": "16px"},
                         children=[html.Div(style={"width": "10px", "height": "10px", "borderRadius": "50%",
                                                    "backgroundColor": color}),
                                   html.Div(label, style={"fontSize": "13px", "fontWeight": "600", "color": G_TEXT})]),
                g_stat("Min", series.min(), unit), g_stat("Max", series.max(), unit),
                g_stat("Ort", series.mean(), unit), g_stat("Var", series.var(), unit + "²"),
            ])
        return html.Div(
            style={"display": "flex", "backgroundColor": G_PANEL, "border": f"1px solid {G_BORDER}",
                   "borderRadius": "8px", "marginBottom": "16px", "overflow": "hidden"},
            children=[html.Div(dcc.Graph(figure=fig, config={"displayModeBar": False}),
                               style={"flex": "1", "minWidth": "0"}), stats_panel])

    count   = f"{len(df)} veri noktası" if df is not None else ""
    updated = "Son güncelleme: " + datetime.now(TZ_TR).strftime("%H:%M:%S")

    header = html.Div(
        style={"display": "flex", "justifyContent": "space-between", "alignItems": "center",
               "borderBottom": f"1px solid {G_BORDER}", "paddingBottom": "16px", "marginBottom": "24px"},
        children=[
            html.Div(style={"display": "flex", "alignItems": "center", "gap": "12px"}, children=[
                html.Div(style={"width": "28px", "height": "28px", "borderRadius": "6px",
                                "background": "linear-gradient(135deg,#e95f2b,#e8a838)",
                                "display": "flex", "alignItems": "center", "justifyContent": "center"},
                         children=html.Span("◈", style={"color": "white", "fontSize": "14px"})),
                html.Div([html.Div("IoT Sensör Paneli",
                                   style={"fontSize": "18px", "fontWeight": "700", "color": G_TEXT}),
                          html.Div("Takım 7 / IOT", style={"fontSize": "12px", "color": G_MUTED})]),
            ]),
            html.Div(style={"display": "flex", "alignItems": "center", "gap": "20px"}, children=[
                html.Div(count,   style={"fontSize": "12px", "color": G_MUTED}),
                html.Div(updated, style={"fontSize": "12px", "color": G_MUTED}),
                html.Div(style={"display": "flex", "alignItems": "center", "gap": "6px",
                                "backgroundColor": "#052e16", "border": "1px solid #16a34a",
                                "borderRadius": "4px", "padding": "4px 10px"}, children=[
                    html.Div(style={"width": "7px", "height": "7px", "borderRadius": "50%",
                                    "backgroundColor": G_GREEN, "animation": "pulse 2s infinite"}),
                    html.Span("LIVE", style={"fontSize": "11px", "fontWeight": "700",
                                             "color": G_GREEN, "letterSpacing": "0.1em"}),
                ]),
            ]),
        ])

    if df is None or df.empty:
        body = html.Div("Henüz veri yok...", style={"color": G_MUTED})
    else:
        body = [make_row(df, col, label, unit, color, fill) for col, label, unit, color, fill in SENSORS]

    return html.Div(style={"padding": "24px"}, children=[header, html.Div(body)])

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8050, debug=False)
