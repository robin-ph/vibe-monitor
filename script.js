// ─── Vibe Monitor Dashboard v3.1 ───

const COLORS = {
    thinking: "#a78bfa",
    tool: "#fbbf24",
    output: "#38bdf8",
    network: "#fb7185",
    unaccounted: "#94a3b8",
};

let turns = [];
let chart = null;
let pieChart = null;
let ws = null;
let activeTimer = null;

// ─── Project Filter State ───

const PROJECT_COLORS = [
    "#818cf8", "#34d399", "#fb923c", "#f472b6",
    "#22d3ee", "#a78bfa", "#facc15", "#fb7185",
];
const projectColorMap = {};
let projectColorIdx = 0;
let activeProjectFilter = null; // null = show all

function getProjectColor(name) {
    if (!projectColorMap[name]) {
        projectColorMap[name] = PROJECT_COLORS[projectColorIdx % PROJECT_COLORS.length];
        projectColorIdx++;
    }
    return projectColorMap[name];
}

function getFilteredTurns() {
    if (!activeProjectFilter) return turns;
    return turns.filter(t => (t.project_name || "Unknown") === activeProjectFilter);
}

// ─── Date Navigation State ───

let todayStr = "";          // "2026-03-07" — set by server
let viewingDate = "";       // "" = live today, or "2026-03-05" for history
let availableDates = [];    // ["2026-03-07", "2026-03-06", ...] sorted desc

function isViewingToday() {
    return !viewingDate || viewingDate === todayStr;
}

// ─── WebSocket ───

function connect() {
    const statusEl = document.getElementById("ws-status");
    ws = new WebSocket(`ws://${location.host}/ws`);

    ws.onopen = () => {
        statusEl.textContent = "Connected";
        statusEl.classList.add("connected");
    };

    ws.onclose = () => {
        statusEl.textContent = "Disconnected";
        statusEl.classList.remove("connected");
        setTimeout(connect, 3000);
    };

    ws.onmessage = (e) => {
        const msg = JSON.parse(e.data);
        handleMessage(msg);
    };
}

function handleMessage(msg) {
    // Only process live updates when viewing today
    if (!isViewingToday() && msg.type !== "init") return;

    switch (msg.type) {
        case "init":
            todayStr = msg.date || new Date().toISOString().slice(0, 10);
            if (isViewingToday()) {
                turns = msg.turns || [];
                renderAll();
                if (msg.active) showActiveTurn();
            }
            loadAvailableDates();
            break;

        case "turn_start":
            showActiveTurn(msg.turn_number);
            break;

        case "tool_start":
            updateActiveTool(msg.tool, msg.detail);
            break;

        case "tool_end":
            updateActiveTool(null);
            break;

        case "turn_complete":
            hideActiveTurn();
            turns.push(msg.data);
            renderAll();
            break;

        case "reset":
            turns = [];
            hideActiveTurn();
            renderAll();
            loadAvailableDates();
            break;
    }
}

// ─── Date Navigation ───

async function loadAvailableDates() {
    try {
        const resp = await fetch("/api/history");
        const data = await resp.json();
        todayStr = data.today;
        availableDates = [todayStr, ...data.archives.map(a => a.date)];
        updateDateNav();
    } catch (e) {
        console.error("Failed to load history:", e);
    }
}

async function switchToDate(dateStr) {
    if (dateStr === todayStr) {
        // Back to live
        viewingDate = "";
        // Re-fetch today's live data
        try {
            const resp = await fetch("/api/turns");
            const data = await resp.json();
            turns = data.turns || [];
        } catch (e) {
            turns = [];
        }
        renderAll();
        updateDateNav();
        return;
    }

    // Load historical data
    viewingDate = dateStr;
    hideActiveTurn();

    try {
        const resp = await fetch(`/api/history/${dateStr}`);
        const data = await resp.json();
        if (data.error) {
            turns = [];
        } else {
            turns = data.turns || [];
        }
    } catch (e) {
        turns = [];
    }

    renderAll();
    updateDateNav();
}

function updateDateNav() {
    const display = document.getElementById("date-display");
    const prevBtn = document.getElementById("date-prev");
    const nextBtn = document.getElementById("date-next");
    const todayBtn = document.getElementById("date-today");

    const current = isViewingToday() ? todayStr : viewingDate;
    const idx = availableDates.indexOf(current);

    // Display date
    if (isViewingToday()) {
        display.textContent = `Today \u00b7 ${formatDateShort(todayStr)}`;
        display.classList.remove("is-history");
        todayBtn.style.display = "none";
    } else {
        display.textContent = formatDateShort(viewingDate);
        display.classList.add("is-history");
        todayBtn.style.display = "flex";
    }

    // Prev: go to older date (higher index)
    prevBtn.disabled = idx < 0 || idx >= availableDates.length - 1;
    // Next: go to newer date (lower index), hidden if already on today
    nextBtn.disabled = idx <= 0;
}

function formatDateShort(dateStr) {
    if (!dateStr) return "";
    try {
        const d = new Date(dateStr + "T12:00:00");
        const month = d.toLocaleDateString("en", { month: "short" });
        const day = d.getDate();
        const weekday = d.toLocaleDateString("en", { weekday: "short" });
        return `${weekday}, ${month} ${day}`;
    } catch {
        return dateStr;
    }
}

function initDateNav() {
    document.getElementById("date-prev").addEventListener("click", () => {
        const current = isViewingToday() ? todayStr : viewingDate;
        const idx = availableDates.indexOf(current);
        if (idx >= 0 && idx < availableDates.length - 1) {
            switchToDate(availableDates[idx + 1]);
        }
    });

    document.getElementById("date-next").addEventListener("click", () => {
        const current = isViewingToday() ? todayStr : viewingDate;
        const idx = availableDates.indexOf(current);
        if (idx > 0) {
            switchToDate(availableDates[idx - 1]);
        }
    });

    document.getElementById("date-today").addEventListener("click", () => {
        switchToDate(todayStr);
    });
}

// ─── Active Turn Indicator ───

function showActiveTurn(turnNum) {
    if (!isViewingToday()) return;
    const el = document.getElementById("active-turn");
    el.style.display = "flex";
    if (turnNum) {
        document.getElementById("active-turn-num").textContent = turnNum;
    }

    const startTime = Date.now();
    clearInterval(activeTimer);
    activeTimer = setInterval(() => {
        const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
        document.getElementById("active-elapsed").textContent = `${elapsed}s`;
    }, 100);
}

function hideActiveTurn() {
    document.getElementById("active-turn").style.display = "none";
    clearInterval(activeTimer);
}

function updateActiveTool(toolName, detail) {
    const el = document.getElementById("active-tool");
    if (toolName) {
        el.textContent = `${toolName}${detail ? ": " + detail : ""}`;
        el.style.display = "inline";
    } else {
        el.textContent = "";
    }
}

// ─── Render All ───

function renderAll() {
    renderProjectFilter();
    renderSummary();
    renderChart();
    renderTurnList();
}

// ─── Project Filter ───

function renderProjectFilter() {
    const container = document.getElementById("project-filter");
    const projects = {};
    turns.forEach(t => {
        const name = t.project_name || "Unknown";
        projects[name] = (projects[name] || 0) + 1;
    });

    const names = Object.keys(projects);
    if (names.length <= 1) {
        container.style.display = "none";
        // Auto-clear filter if only one project
        if (names.length === 1 && activeProjectFilter) activeProjectFilter = null;
        return;
    }

    container.style.display = "flex";
    const allActive = !activeProjectFilter;

    let html = `<span class="project-chip ${allActive ? 'active' : ''}" data-project=""
        style="background:${allActive ? 'rgba(148,163,184,0.12)' : 'transparent'}; color:var(--text-secondary); border-color:${allActive ? 'var(--text-dim)' : 'var(--border)'}">
        All <span class="chip-count">${turns.length}</span></span>`;

    names.sort((a, b) => projects[b] - projects[a]);
    for (const name of names) {
        const color = getProjectColor(name);
        const isActive = activeProjectFilter === name;
        html += `<span class="project-chip ${isActive ? 'active' : ''}" data-project="${name}"
            style="background:${isActive ? color + '18' : 'transparent'}; color:${color}; border-color:${isActive ? color + '60' : color + '30'}">
            ${name} <span class="chip-count">${projects[name]}</span></span>`;
    }

    container.innerHTML = html;

    // Attach click handlers
    container.querySelectorAll(".project-chip").forEach(chip => {
        chip.addEventListener("click", () => {
            const proj = chip.dataset.project;
            activeProjectFilter = proj || null;
            renderAll();
        });
    });
}

// ─── Summary Stats ───

function renderSummary() {
    const filtered = getFilteredTurns();
    document.getElementById("total-turns").textContent = filtered.length;

    const totalTime = filtered.reduce((s, t) => s + t.total_time, 0);
    document.getElementById("total-time").textContent = formatTime(totalTime);

    const turnsWithThinking = filtered.filter((t) => t.thinking_tps > 0);
    const avgTps =
        turnsWithThinking.length > 0
            ? turnsWithThinking.reduce((s, t) => s + t.thinking_tps, 0) /
              turnsWithThinking.length
            : 0;
    document.getElementById("avg-tps").textContent = avgTps.toFixed(0);

    // Pie chart data
    const totalThinking = filtered.reduce((s, t) => s + t.thinking_time, 0);
    const totalTool = filtered.reduce((s, t) => s + t.tool_time, 0);
    const totalOutput = filtered.reduce((s, t) => s + (t.output_time || 0), 0);
    const totalNetwork = filtered.reduce((s, t) => s + (t.network_time || 0), 0);
    const totalUnaccounted = filtered.reduce((s, t) => s + (t.unaccounted_time || 0), 0);
    const totalOverhead = totalNetwork + totalUnaccounted;

    renderPieChart([totalThinking, totalTool, totalOutput, totalOverhead]);
}

function renderPieChart(data) {
    const ctx = document.getElementById("pieChart").getContext("2d");
    const labels = ["Thinking", "Tool Use", "Output", "Overhead"];
    const colors = [COLORS.thinking, COLORS.tool, COLORS.output, COLORS.network];
    const total = data.reduce((s, v) => s + v, 0);

    if (pieChart) pieChart.destroy();

    if (total === 0) {
        pieChart = new Chart(ctx, {
            type: "doughnut",
            data: {
                labels: ["No data"],
                datasets: [{
                    data: [1],
                    backgroundColor: ["rgba(148, 163, 184, 0.1)"],
                    borderWidth: 0,
                }],
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                cutout: "60%",
                plugins: {
                    legend: { display: false },
                    tooltip: { enabled: false },
                },
            },
        });
        return;
    }

    pieChart = new Chart(ctx, {
        type: "doughnut",
        data: {
            labels,
            datasets: [{
                data,
                backgroundColor: colors.map(c => c + "cc"),
                hoverBackgroundColor: colors,
                borderWidth: 2,
                borderColor: "#151c27",
                hoverBorderColor: "#e2e8f0",
                hoverBorderWidth: 2,
                borderRadius: 3,
                spacing: 2,
            }],
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            cutout: "58%",
            plugins: {
                legend: {
                    display: true,
                    position: "right",
                    labels: {
                        color: "#64748b",
                        font: { family: "'Inter', sans-serif", size: 11, weight: "500" },
                        padding: 10,
                        usePointStyle: true,
                        pointStyleWidth: 8,
                        generateLabels: (chart) => {
                            const ds = chart.data.datasets[0];
                            return chart.data.labels.map((label, i) => {
                                const val = ds.data[i];
                                const pct = total > 0 ? ((val / total) * 100).toFixed(0) : 0;
                                return {
                                    text: `${label}  ${pct}%`,
                                    fontColor: colors[i],
                                    fillStyle: colors[i],
                                    strokeStyle: "transparent",
                                    pointStyle: "circle",
                                    index: i,
                                };
                            });
                        },
                    },
                },
                tooltip: {
                    backgroundColor: "#1e293b",
                    titleColor: "#e2e8f0",
                    bodyColor: "#94a3b8",
                    borderColor: "#334155",
                    borderWidth: 1,
                    cornerRadius: 8,
                    padding: 10,
                    callbacks: {
                        label: (ctx) => {
                            const val = ctx.parsed;
                            const pct = total > 0 ? ((val / total) * 100).toFixed(1) : 0;
                            return ` ${ctx.label}: ${val.toFixed(1)}s (${pct}%)`;
                        },
                    },
                },
            },
        },
    });
}

// ─── Chart ───

function renderChart() {
    const ctx = document.getElementById("turnChart").getContext("2d");
    const filtered = getFilteredTurns();

    const labels = filtered.map((t) => `T${t.turn_number}`);
    const thinkingData = filtered.map((t) => t.thinking_time);
    const toolData = filtered.map((t) => t.tool_time);
    const outputData = filtered.map((t) => t.output_time || 0);
    const networkData = filtered.map((t) => t.network_time || 0);
    const unaccountedData = filtered.map((t) => t.unaccounted_time || 0);

    if (chart) chart.destroy();

    chart = new Chart(ctx, {
        type: "bar",
        data: {
            labels,
            datasets: [
                {
                    label: "Thinking",
                    data: thinkingData,
                    backgroundColor: COLORS.thinking + "cc",
                    hoverBackgroundColor: COLORS.thinking,
                    borderRadius: 2,
                },
                {
                    label: "Tool Use",
                    data: toolData,
                    backgroundColor: COLORS.tool + "cc",
                    hoverBackgroundColor: COLORS.tool,
                    borderRadius: 2,
                },
                {
                    label: "Output",
                    data: outputData,
                    backgroundColor: COLORS.output + "cc",
                    hoverBackgroundColor: COLORS.output,
                    borderRadius: 2,
                },
                {
                    label: "Network",
                    data: networkData,
                    backgroundColor: COLORS.network + "cc",
                    hoverBackgroundColor: COLORS.network,
                    borderRadius: 2,
                },
                {
                    label: "Unaccounted",
                    data: unaccountedData,
                    backgroundColor: COLORS.unaccounted + "66",
                    hoverBackgroundColor: COLORS.unaccounted,
                    borderRadius: 2,
                },
            ],
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            indexAxis: "y",
            scales: {
                x: {
                    stacked: true,
                    title: {
                        display: true,
                        text: "Seconds",
                        color: "#64748b",
                        font: { size: 11, weight: "500" },
                    },
                    grid: { color: "rgba(148, 163, 184, 0.06)" },
                    ticks: { color: "#64748b", font: { size: 11 } },
                    border: { color: "rgba(148, 163, 184, 0.1)" },
                },
                y: {
                    stacked: true,
                    grid: { display: false },
                    ticks: {
                        color: "#94a3b8",
                        font: { family: "'JetBrains Mono', monospace", size: 11, weight: "500" },
                    },
                    border: { display: false },
                },
            },
            plugins: {
                legend: { display: false },
                tooltip: {
                    backgroundColor: "#1e293b",
                    titleColor: "#e2e8f0",
                    bodyColor: "#94a3b8",
                    borderColor: "#334155",
                    borderWidth: 1,
                    cornerRadius: 8,
                    padding: 10,
                    callbacks: {
                        label: (ctx) => ` ${ctx.dataset.label}: ${ctx.parsed.x.toFixed(1)}s`,
                        afterBody: (items) => {
                            const idx = items[0].dataIndex;
                            const t = getFilteredTurns()[idx];
                            if (!t) return "";
                            const lines = [``, `Total: ${t.total_time.toFixed(1)}s`];
                            if (t.thinking_tps > 0) {
                                lines.push(`Thinking: ${t.thinking_tokens} tok @ ${t.thinking_tps} tok/s`);
                            }
                            if (t.tool_count > 0) {
                                const bd = Object.entries(t.tool_breakdown || {})
                                    .map(([k, v]) => `${shortToolName(k)}x${v}`)
                                    .join(", ");
                                lines.push(`Tools: ${bd}`);
                            }
                            return lines;
                        },
                    },
                },
            },
        },
    });
}

// ─── Turn List ───

function renderTurnList() {
    const container = document.getElementById("turn-list");
    const filtered = getFilteredTurns();

    if (filtered.length === 0) {
        const msg = isViewingToday()
            ? "No turns recorded yet. Start a conversation in Claude Code."
            : "No data recorded for this date.";
        container.innerHTML = `<div class="empty-state">${msg}</div>`;
        return;
    }

    const hasMultipleProjects = new Set(turns.map(t => t.project_name || "Unknown")).size > 1;
    container.innerHTML = [...filtered]
        .reverse()
        .map((t) => renderTurnCard(t, hasMultipleProjects))
        .join("");
}

function shortToolName(name) {
    if (name.startsWith("mcp__")) {
        const parts = name.replace("mcp__", "").split("__");
        const server = parts[0].replace("Claude_in_Chrome", "Chrome").replace("Claude_Preview", "Preview");
        return parts.length > 1 ? `${server}:${parts.slice(1).join("_")}` : server;
    }
    return name;
}

// Assign a stable color per tool name
const TOOL_COLORS = [
    "#fbbf24", "#fb923c", "#f87171", "#a78bfa",
    "#34d399", "#38bdf8", "#e879f9", "#fb7185",
    "#4ade80", "#2dd4bf", "#c084fc", "#60a5fa",
];
const toolColorMap = {};
let toolColorIdx = 0;
function getToolColor(name) {
    if (!toolColorMap[name]) {
        toolColorMap[name] = TOOL_COLORS[toolColorIdx % TOOL_COLORS.length];
        toolColorIdx++;
    }
    return toolColorMap[name];
}

function renderTurnCard(t, showProject = false) {
    const thinkPct = t.total_time > 0 ? (t.thinking_time / t.total_time) * 100 : 0;
    const toolPct = t.total_time > 0 ? (t.tool_time / t.total_time) * 100 : 0;
    const outputPct = t.total_time > 0 ? ((t.output_time || 0) / t.total_time) * 100 : 0;
    const netPct = t.total_time > 0 ? ((t.network_time || 0) / t.total_time) * 100 : 0;
    const unaccPct = t.total_time > 0 ? ((t.unaccounted_time || 0) / t.total_time) * 100 : 0;

    const tpsBadge =
        t.thinking_tps > 0
            ? `<span class="tps-badge">${t.thinking_tps} tok/s</span>`
            : "";

    const toolRows = (t.tools || [])
        .slice()
        .sort((a, b) => b.duration - a.duration)
        .map((tool) => {
            const pct = t.tool_time > 0 ? (tool.duration / t.tool_time) * 100 : 0;
            const color = getToolColor(tool.tool);
            const short = shortToolName(tool.tool);
            const detail = tool.detail ? ` <span class="dim">${tool.detail}</span>` : "";
            return `
            <div class="tool-row">
                <div class="tool-row-bar" style="width:${pct}%; background:${color};"></div>
                <span class="tool-row-name" style="color:${color}">${short}</span>${detail}
                <span class="tool-row-dur">${tool.duration.toFixed(2)}s</span>
            </div>`;
        })
        .join("");

    const toolTags = Object.entries(t.tool_breakdown || {})
        .sort((a, b) => b[1] - a[1])
        .map(([name, count]) => {
            const color = getToolColor(name);
            const short = shortToolName(name);
            const dur = (t.tools || [])
                .filter((x) => x.tool === name)
                .reduce((s, x) => s + x.duration, 0);
            return `<span class="tool-tag" style="background:${color}12; color:${color}; border-color:${color}30">
                ${short} <span class="tool-count">${count}x</span> <span class="tool-dur">${dur.toFixed(1)}s</span>
            </span>`;
        })
        .join("");

    const projName = t.project_name || "Unknown";
    const projColor = getProjectColor(projName);
    const projBadge = showProject
        ? `<span class="project-badge" style="background:${projColor}18; color:${projColor}; border:1px solid ${projColor}30">${projName}</span>`
        : "";

    return `
    <div class="turn-card">
        <div class="turn-header">
            <div class="turn-title">
                <span class="turn-num">Turn ${t.turn_number}</span>
                ${tpsBadge}
                ${projBadge}
            </div>
            <span class="turn-total">${t.total_time.toFixed(1)}s</span>
        </div>

        <div class="turn-bar">
            <div class="bar-segment thinking" style="width:${thinkPct}%" title="Thinking: ${t.thinking_time.toFixed(1)}s"></div>
            <div class="bar-segment tool" style="width:${toolPct}%" title="Tool Use: ${t.tool_time.toFixed(1)}s"></div>
            <div class="bar-segment output" style="width:${outputPct}%" title="Output: ${(t.output_time||0).toFixed(1)}s"></div>
            <div class="bar-segment network" style="width:${netPct}%" title="Network: ${(t.network_time||0).toFixed(1)}s"></div>
            <div class="bar-segment unaccounted" style="width:${unaccPct}%" title="Unaccounted: ${(t.unaccounted_time||0).toFixed(1)}s"></div>
        </div>

        <div class="turn-details">
            <div class="detail-item">
                <span class="dot" style="background:${COLORS.thinking}"></span>
                Thinking: <strong>${t.thinking_time.toFixed(1)}s</strong>
                ${t.thinking_tokens > 0 ? `<span class="dim">(${t.thinking_tokens} tok)</span>` : ""}
            </div>
            <div class="detail-item">
                <span class="dot" style="background:${COLORS.tool}"></span>
                Tool: <strong>${t.tool_time.toFixed(1)}s</strong>
                <span class="dim">(${t.tool_count} calls${t.tool_time_recovered > 0 ? `, +${t.tool_time_recovered.toFixed(1)}s recovered` : ""})</span>
            </div>
            <div class="detail-item">
                <span class="dot" style="background:${COLORS.output}"></span>
                Output: <strong>${(t.output_time||0).toFixed(1)}s</strong>
            </div>
            <div class="detail-item">
                <span class="dot" style="background:${COLORS.network}"></span>
                Network: <strong>${(t.network_time||0).toFixed(1)}s</strong>
                <span class="dim">(${t.api_calls || 1} API)</span>
            </div>
            ${(t.unaccounted_time || 0) > 0.5 ? `
            <div class="detail-item">
                <span class="dot" style="background:${COLORS.unaccounted}"></span>
                Other: <strong>${(t.unaccounted_time||0).toFixed(1)}s</strong>
            </div>` : ""}
        </div>

        ${toolTags ? `<div class="tool-tags">${toolTags}</div>` : ""}

        ${toolRows ? `<div class="tool-detail-section">${toolRows}</div>` : ""}
    </div>`;
}

// ─── Helpers ───

function formatTime(seconds) {
    if (seconds < 60) return `${seconds.toFixed(1)}s`;
    const m = Math.floor(seconds / 60);
    const s = (seconds % 60).toFixed(0);
    return `${m}m ${s}s`;
}

// ─── Init ───

document.getElementById("reset-btn").addEventListener("click", async () => {
    if (!isViewingToday()) return;
    if (confirm("Reset all turn data?")) {
        await fetch("/api/reset", { method: "POST" });
    }
});

initDateNav();
connect();
