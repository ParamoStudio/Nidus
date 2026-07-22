//
//  MicroToolDefaults.swift
//  Nidus
//
//  The built-in micro-tool(s), shipped as plain `.js` seeded into the vault's `_microtools/` on first
//  run — so the very first tool goes through the EXACT same importable pipeline a community tool
//  would, and doubles as the reference example for the "toolmaker" authoring guide. Built-ins are
//  protected (can't be uninstalled) and re-seed if their file is missing.
//
//  Contract a micro-tool `.js` must follow: define a global `tool` with { id, name, icon (SF Symbol),
//  summary, inputs[], render(data) }. `inputs` is the form SCHEMA the app renders generically:
//    - { key, type: "text"|"textarea"|"number", label, placeholder }
//    - { key, type: "table", label, addLabel, columns: [{ key, label, type: "text"|"number" }] }
//    - { key, type: "grid", label, rows, cols }  → an editable grid that grows both ways; render
//      receives data[key] as a 2D array of strings (rows of cells), first row conventionally the header.
//  `render(data)` is a PURE function: scalars arrive as strings, tables as arrays of { column: string },
//  grids as [[string]] (do your own parseFloat), and it returns a Markdown string. No filesystem/
//  network/system access exists in the context — keep it to computation + string building.
//

let recipeNormalizerJS = """
var tool = {
  id: "recipe-normalizer",
  name: "Recipe Normalizer",
  icon: "percent",
  summary: "Normalize any technical recipe — glazes, clay bodies, cocktails, chemicals, paints — to a base of 100, with additives as a percentage, and export it as a clean Markdown table.",
  inputs: [
    { key: "title", type: "text", label: "Recipe name", placeholder: "e.g. Base #1" },
    { key: "base", type: "table", label: "Base materials", addLabel: "Add material",
      columns: [
        { key: "material", label: "Material", type: "text" },
        { key: "amount", label: "Amount", type: "number" }
      ] },
    { key: "additives", type: "table", label: "Additives (% of base, not normalized)", addLabel: "Add additive",
      columns: [
        { key: "material", label: "Additive", type: "text" },
        { key: "amount", label: "%", type: "number" }
      ] }
  ],
  render: function(data) {
    function num(x) { var v = parseFloat(x); return isNaN(v) ? 0 : v; }
    function fmt(x) { return x.toFixed(2); }
    var base = (data.base || []).filter(function(r) { return r.material && r.material.trim() && num(r.amount) > 0; });
    var adds = (data.additives || []).filter(function(r) { return r.material && r.material.trim() && num(r.amount) !== 0; });
    var totalGrams = base.reduce(function(s, r) { return s + num(r.amount); }, 0);

    var lines = [];
    var title = (data.title && data.title.trim()) ? data.title.trim() : "Recipe";
    lines.push("# " + title);
    lines.push("");
    lines.push("| Material | Amount |");
    lines.push("| --- | ---: |");

    if (totalGrams > 0) {
      base.forEach(function(r) {
        lines.push("| " + r.material.trim() + " | " + fmt(num(r.amount) / totalGrams * 100) + " |");
      });
      lines.push("| **Total base recipe** | **100.00** |");
    } else {
      lines.push("| _(no base materials)_ | 0.00 |");
    }

    var addTotal = 0;
    adds.forEach(function(r) {
      addTotal += num(r.amount);
      lines.push("| + " + r.material.trim() + " | " + fmt(num(r.amount)) + " |");
    });
    lines.push("| **Total** | **" + fmt((totalGrams > 0 ? 100 : 0) + addTotal) + "** |");
    return lines.join("\\n");
  }
};
"""

let tableBuilderJS = """
var tool = {
  id: "table-builder",
  name: "Table Builder",
  icon: "tablecells",
  summary: "Build a Markdown table visually — start at 2×2 and grow it row by row and column by column. The first row is the header; a row with only its first cell filled becomes a bold section divider.",
  inputs: [
    { key: "title", type: "text", label: "Title (optional)", placeholder: "e.g. Materials" },
    { key: "grid", type: "grid", label: "Table", rows: 2, cols: 2 }
  ],
  render: function(data) {
    function trim(s) { return (s || "").replace(/^\\s+|\\s+$/g, ""); }
    function isNumericHeader(h) {
      h = trim(h).toLowerCase();
      var exact = ["g","l","n","x","qty","kg","ml","%"];
      for (var i = 0; i < exact.length; i++) { if (h === exact[i]) return true; }
      var partial = ["amount","value","price","cost","quantity","weight","gram","percent","total","score","hours","time","count"];
      for (var j = 0; j < partial.length; j++) { if (h.indexOf(partial[j]) !== -1) return true; }
      return false;
    }
    var g = data.grid || [];
    var lines = [];
    var title = trim(data.title);
    if (title) { lines.push("# " + title); lines.push(""); }
    if (g.length === 0) return lines.join("\\n");

    var cols = 0;
    g.forEach(function(row) { if (row.length > cols) cols = row.length; });
    if (cols === 0) return lines.join("\\n");
    function cell(row, i) { return trim(row && row[i]); }

    var header = g[0] || [];
    var headerLine = "|", alignLine = "|";
    for (var i = 0; i < cols; i++) {
      var h = cell(header, i);
      headerLine += " " + (h || ("Column " + (i + 1))) + " |";
      alignLine += isNumericHeader(h) ? " ---: |" : " --- |";
    }
    lines.push(headerLine);
    lines.push(alignLine);

    for (var r = 1; r < g.length; r++) {
      var row = g[r];
      var any = false;
      for (var i = 0; i < cols; i++) { if (cell(row, i) !== "") { any = true; break; } }
      if (!any) continue;
      var onlyFirst = cell(row, 0) !== "";
      for (var i = 1; i < cols; i++) { if (cell(row, i) !== "") { onlyFirst = false; break; } }
      if (onlyFirst && cols > 1) {
        var line = "| **" + cell(row, 0) + "** |";
        for (var i = 1; i < cols; i++) { line += " |"; }
        lines.push(line);
      } else {
        var line = "|";
        for (var i = 0; i < cols; i++) { line += " " + cell(row, i) + " |"; }
        lines.push(line);
      }
    }
    return lines.join("\\n");
  }
};
"""

let triaxialCalculatorJS = """
var tool = {
  id: "triaxial-calculator",
  name: "Triaxial",
  icon: "triangle",
  summary: "Blend three materials across a triaxial — each corner has its own max (test outside 100%, e.g. an addition). Exports a labelled triangle plus a mixing table.",
  inputs: [
    { key: "title", type: "text", label: "Test name", placeholder: "e.g. Copper triaxial #1", maxLength: 40 },
    { type: "row", fields: [
      { key: "a", type: "text", label: "▲ Top", placeholder: "Base A", maxLength: 14 },
      { key: "amax", type: "number", label: "Max %", placeholder: "100" }
    ] },
    { type: "row", fields: [
      { key: "b", type: "text", label: "◣ Bottom-left", placeholder: "Base B", maxLength: 14 },
      { key: "bmax", type: "number", label: "Max %", placeholder: "100" }
    ] },
    { type: "row", fields: [
      { key: "c", type: "text", label: "◢ Bottom-right", placeholder: "Copper", maxLength: 14 },
      { key: "cmax", type: "number", label: "Max %", placeholder: "100" }
    ] },
    { key: "steps", type: "number", label: "Steps (1–5)", placeholder: "4" }
  ],
  render: function(data) {
    function nm(x, d) { x = (x || "").replace(/^\\s+|\\s+$/g, ""); return x || d; }
    function numOr(x, d) { var v = parseFloat(x); return isNaN(v) ? d : v; }
    function rep(s, n) { var r = ""; for (var k = 0; k < n; k++) { r += s; } return r; }
    function pct(x) { var r = Math.round(x * 10) / 10; return (r % 1 === 0 ? r.toFixed(0) : r.toFixed(1)) + "%"; }

    var A = nm(data.a, "A"), B = nm(data.b, "B"), C = nm(data.c, "C");
    var mA = numOr(data.amax, 100), mB = numOr(data.bmax, 100), mC = numOr(data.cmax, 100);
    var N = parseInt(data.steps, 10);
    if (isNaN(N) || N < 1) { N = 4; }
    if (N > 5) { N = 5; }
    var title = nm(data.title, "Triaxial");

    // Barycentric weights: A=(N-i)/N, B=(i-j)/N, C=j/N. Each corner's value = its max × its weight
    // (so a corner can be an addition up to <100%). Numbered top→bottom, left→right.
    var num = 1, rows = [], pts = [];
    for (var i = 0; i <= N; i++) {
      var row = [];
      for (var j = 0; j <= i; j++) {
        var wA = (N - i) / N, wB = (i - j) / N, wC = j / N;
        row.push(num);
        pts.push({ n: num, A: mA * wA, B: mB * wB, C: mC * wC, wA: wA, wB: wB, wC: wC });
        num++;
      }
      rows.push(row);
    }
    var total = num - 1;
    var vTop = 1, vBL = rows[N][0], vBR = rows[N][N];

    // Centre point(s): closest to the centroid (1/3,1/3,1/3) — one if N divides by 3, else ~3.
    var best = 1e9;
    for (var p = 0; p < pts.length; p++) {
      var dA = pts[p].wA - 1 / 3, dB = pts[p].wB - 1 / 3, dC = pts[p].wC - 1 / 3;
      pts[p].d = dA * dA + dB * dB + dC * dC;
      if (pts[p].d < best) { best = pts[p].d; }
    }
    for (var p = 0; p < pts.length; p++) { pts[p].center = (pts[p].d - best) < 1e-9; }

    var w = String(total).length;
    function pad(n) { var s = String(n); while (s.length < w) { s = " " + s; } return s; }

    var lines = [];
    lines.push("# " + title);
    lines.push("");

    // Triangle with the corner NAMES at their vertices: A centred on top, B inline to the left of the
    // base row and C inline to its right. Everything is shifted right by "B " so it reads balanced.
    var tri = [];
    for (var i = 0; i <= N; i++) {
      var indent = Math.round((N - i) * (w + 1) / 2);
      tri.push(rep(" ", indent) + rows[i].map(pad).join(" "));
    }
    var baseNum = tri[N];               // the base row's numbers (indent 0)
    var LB = B.length + 1;              // width of the "B " prefix
    lines.push("```");
    lines.push(rep(" ", LB + Math.max(0, Math.floor((baseNum.length - A.length) / 2))) + A);
    for (var i = 0; i < N; i++) { lines.push(rep(" ", LB) + tri[i]); }
    lines.push(B + " " + baseNum + " " + C);
    lines.push("```");
    lines.push("");

    // Mixing table: each corner's value at each point; vertices + centre are labelled.
    lines.push("| # | " + A + " | " + B + " | " + C + " |");
    lines.push("| :--- | ---: | ---: | ---: |");
    for (var p = 0; p < pts.length; p++) {
      var lbl = String(pts[p].n);
      if (pts[p].n === vTop) { lbl += " (" + A + ")"; }
      else if (pts[p].n === vBL) { lbl += " (" + B + ")"; }
      else if (pts[p].n === vBR) { lbl += " (" + C + ")"; }
      else if (pts[p].center) { lbl += " (center)"; }
      lines.push("| " + lbl + " | " + pct(pts[p].A) + " | " + pct(pts[p].B) + " | " + pct(pts[p].C) + " |");
    }
    return lines.join("\\n");
  }
};
"""

let batchRenamerJS = """
var tool = {
  id: "batch-renamer",
  name: "Batch Renamer",
  icon: "list.number",
  summary: "Name a batch of tests from a code (Nm → Nm-1, Nm-2…) and track each one's change, tile number and notes in a table.",
  inputs: [
    { key: "title", type: "text", label: "Batch name", placeholder: "e.g. Black manganese tests", maxLength: 48 },
    { key: "batch", type: "batch", label: "Tests", columns: [
      { key: "change", label: "Change / additive" },
      { key: "tile", label: "Tile #" },
      { key: "notes", label: "Notes" }
    ] }
  ],
  render: function(data) {
    function cln(x) { x = (x || "") + ""; return x.split("|").join("\\\\|").replace(/^\\s+|\\s+$/g, ""); }
    var b = data.batch || {};
    var prefix = ((b.prefix || "") + "").replace(/^\\s+|\\s+$/g, "");
    var items = b.items || [];
    var title = ((data.title || "") + "").replace(/^\\s+|\\s+$/g, "");
    var lines = [];
    if (title) { lines.push("# " + title); lines.push(""); }
    lines.push("| Code | Change / additive | Tile # | Notes |");
    lines.push("| :--- | :--- | ---: | :--- |");
    for (var i = 0; i < items.length; i++) {
      var it = items[i];
      var code = (prefix || "Test") + "-" + it.n;
      lines.push("| **" + code + "** | " + cln(it.change) + " | " + cln(it.tile) + " | " + cln(it.notes) + " |");
    }
    if (items.length === 0) { lines.push("| _(no tests)_ |  |  |  |"); }
    return lines.join("\\n");
  }
};
"""

let templateLibraryJS = """
var tool = {
  id: "template-library",
  name: "Template Library",
  icon: "square.stack",
  summary: "Pick from 11 templates and export structured Markdown with section headings.",
  inputs: [
    { key: "template", type: "picker", label: "Template", options: [
      { value: "documentation", label: "Documentation", description: "Explain how something works, for others (or future you)." },
      { value: "decision", label: "Decision Record", description: "Record a decision, the alternatives you weighed, and why." },
      { value: "experiment", label: "Experiment", description: "Test a hypothesis and log what happened." },
      { value: "meeting", label: "Meeting Notes", description: "Capture what was discussed, decided, and who owns what." },
      { value: "interview", label: "Interview", description: "Write up what someone told you and what you learned." },
      { value: "pros", label: "Pros / Cons", description: "Weigh two options side by side before deciding." },
      { value: "specification", label: "Specification Sheet", description: "Define measurable specs for something you're building." },
      { value: "material", label: "Material Entry", description: "Catalog a raw material or supply and its properties." },
      { value: "reference", label: "Reference Note", description: "Save what you learned from a source, in your own words." },
      { value: "feature", label: "Feature Request", description: "Propose something new and the problem it solves." },
      { value: "changelog", label: "Changelog Entry", description: "Log what changed in a version, for future reference." }
    ] },

    { key: "doc_title", type: "text", label: "Title", placeholder: "e.g. Glaze Testing Protocol", showWhen: { key: "template", equals: "documentation" } },
    { key: "doc_summary", type: "textarea", label: "Summary", showWhen: { key: "template", equals: "documentation" } },
    { key: "doc_specifications", type: "textarea", label: "Specifications", showWhen: { key: "template", equals: "documentation" } },
    { key: "doc_notes", type: "textarea", label: "Notes", showWhen: { key: "template", equals: "documentation" } },

    { key: "dec_decision", type: "text", label: "Decision", placeholder: "e.g. Adopt SQLite", showWhen: { key: "template", equals: "decision" } },
    { key: "dec_context", type: "textarea", label: "Context", showWhen: { key: "template", equals: "decision" } },
    { key: "dec_alternatives", type: "textarea", label: "Alternatives", showWhen: { key: "template", equals: "decision" } },
    { key: "dec_reason", type: "textarea", label: "Reason", showWhen: { key: "template", equals: "decision" } },
    { key: "dec_consequences", type: "textarea", label: "Consequences", showWhen: { key: "template", equals: "decision" } },

    { key: "exp_title", type: "text", label: "Title", placeholder: "e.g. Cobalt saturation test", showWhen: { key: "template", equals: "experiment" } },
    { key: "exp_hypothesis", type: "textarea", label: "Hypothesis", showWhen: { key: "template", equals: "experiment" } },
    { key: "exp_variables", type: "textarea", label: "Variables", showWhen: { key: "template", equals: "experiment" } },
    { key: "exp_procedure", type: "textarea", label: "Procedure", showWhen: { key: "template", equals: "experiment" } },
    { key: "exp_results", type: "textarea", label: "Results", showWhen: { key: "template", equals: "experiment" } },
    { key: "exp_conclusion", type: "textarea", label: "Conclusion", showWhen: { key: "template", equals: "experiment" } },

    { key: "meet_title", type: "text", label: "Title", placeholder: "e.g. Sprint planning", showWhen: { key: "template", equals: "meeting" } },
    { key: "meet_participants", type: "textarea", label: "Participants", showWhen: { key: "template", equals: "meeting" } },
    { key: "meet_decisions", type: "textarea", label: "Decisions", showWhen: { key: "template", equals: "meeting" } },
    { key: "meet_actions", type: "textarea", label: "Action Items", showWhen: { key: "template", equals: "meeting" } },
    { key: "meet_notes", type: "textarea", label: "Notes", showWhen: { key: "template", equals: "meeting" } },

    { key: "int_interviewee", type: "text", label: "Interviewee", placeholder: "e.g. Maria González", showWhen: { key: "template", equals: "interview" } },
    { key: "int_context", type: "textarea", label: "Context", showWhen: { key: "template", equals: "interview" } },
    { key: "int_questions", type: "textarea", label: "Questions", showWhen: { key: "template", equals: "interview" } },
    { key: "int_insights", type: "textarea", label: "Key Insights", showWhen: { key: "template", equals: "interview" } },
    { key: "int_followup", type: "textarea", label: "Follow-up", showWhen: { key: "template", equals: "interview" } },

    { key: "pros_subject", type: "text", label: "Subject", placeholder: "e.g. Brent vs Bailey wheel", showWhen: { key: "template", equals: "pros" } },
    { key: "pros_pros", type: "textarea", label: "Pros", showWhen: { key: "template", equals: "pros" } },
    { key: "pros_cons", type: "textarea", label: "Cons", showWhen: { key: "template", equals: "pros" } },
    { key: "pros_conclusion", type: "textarea", label: "Conclusion", showWhen: { key: "template", equals: "pros" } },

    { key: "spec_name", type: "text", label: "Name", placeholder: "e.g. Stoneware body #3", showWhen: { key: "template", equals: "specification" } },
    { key: "spec_version", type: "text", label: "Version", placeholder: "e.g. 1.2", showWhen: { key: "template", equals: "specification" } },
    { key: "spec_dimensions", type: "textarea", label: "Dimensions", showWhen: { key: "template", equals: "specification" } },
    { key: "spec_materials", type: "textarea", label: "Materials", showWhen: { key: "template", equals: "specification" } },
    { key: "spec_properties", type: "textarea", label: "Properties", showWhen: { key: "template", equals: "specification" } },
    { key: "spec_notes", type: "textarea", label: "Notes", showWhen: { key: "template", equals: "specification" } },

    { key: "mat_material", type: "text", label: "Material", placeholder: "e.g. Silica sand 200 mesh", showWhen: { key: "template", equals: "material" } },
    { key: "mat_supplier", type: "text", label: "Supplier", placeholder: "e.g. Cerámica Colón", showWhen: { key: "template", equals: "material" } },
    { key: "mat_properties", type: "textarea", label: "Properties", showWhen: { key: "template", equals: "material" } },
    { key: "mat_applications", type: "textarea", label: "Applications", showWhen: { key: "template", equals: "material" } },
    { key: "mat_notes", type: "textarea", label: "Notes", showWhen: { key: "template", equals: "material" } },

    { key: "ref_source", type: "text", label: "Source", placeholder: "e.g. Hamer — The Potter's Dictionary", showWhen: { key: "template", equals: "reference" } },
    { key: "ref_summary", type: "textarea", label: "Summary", showWhen: { key: "template", equals: "reference" } },
    { key: "ref_keyideas", type: "textarea", label: "Key Ideas", showWhen: { key: "template", equals: "reference" } },
    { key: "ref_quotes", type: "textarea", label: "Quotes", showWhen: { key: "template", equals: "reference" } },
    { key: "ref_personal", type: "textarea", label: "Personal Notes", showWhen: { key: "template", equals: "reference" } },

    { key: "feat_feature", type: "text", label: "Feature", placeholder: "e.g. Batch export to CSV", showWhen: { key: "template", equals: "feature" } },
    { key: "feat_problem", type: "textarea", label: "Problem", showWhen: { key: "template", equals: "feature" } },
    { key: "feat_proposal", type: "textarea", label: "Proposal", showWhen: { key: "template", equals: "feature" } },
    { key: "feat_benefit", type: "textarea", label: "Expected Benefit", showWhen: { key: "template", equals: "feature" } },
    { key: "feat_notes", type: "textarea", label: "Notes", showWhen: { key: "template", equals: "feature" } },

    { key: "change_version", type: "text", label: "Version", placeholder: "e.g. 2.1.0", showWhen: { key: "template", equals: "changelog" } },
    { key: "change_date", type: "text", label: "Date", placeholder: "e.g. 2026-07-05", showWhen: { key: "template", equals: "changelog" } },
    { key: "change_added", type: "textarea", label: "Added", showWhen: { key: "template", equals: "changelog" } },
    { key: "change_changed", type: "textarea", label: "Changed", showWhen: { key: "template", equals: "changelog" } },
    { key: "change_fixed", type: "textarea", label: "Fixed", showWhen: { key: "template", equals: "changelog" } },
    { key: "change_notes", type: "textarea", label: "Notes", showWhen: { key: "template", equals: "changelog" } }
  ],
  render: function(data) {
    function trim(s) { return (s || "").replace(/^\\s+|\\s+$/g, ""); }
    // A blank field is skipped entirely (heading and all) — same as typing "--" explicitly.
    function isSkip(s) { var t = trim(s); return t === "" || t === "--"; }

    var T = {
      documentation: { def: "Documentation", titleKey: "doc_title",
        sections: [
          { key: "doc_summary", label: "Summary" },
          { key: "doc_specifications", label: "Specifications" },
          { key: "doc_notes", label: "Notes" }
        ] },
      decision: { def: "Decision Record", titleKey: "dec_decision",
        sections: [
          { key: "dec_context", label: "Context" },
          { key: "dec_alternatives", label: "Alternatives" },
          { key: "dec_reason", label: "Reason" },
          { key: "dec_consequences", label: "Consequences" }
        ] },
      experiment: { def: "Experiment", titleKey: "exp_title",
        sections: [
          { key: "exp_hypothesis", label: "Hypothesis" },
          { key: "exp_variables", label: "Variables" },
          { key: "exp_procedure", label: "Procedure" },
          { key: "exp_results", label: "Results" },
          { key: "exp_conclusion", label: "Conclusion" }
        ] },
      meeting: { def: "Meeting Notes", titleKey: "meet_title",
        sections: [
          { key: "meet_participants", label: "Participants" },
          { key: "meet_decisions", label: "Decisions" },
          { key: "meet_actions", label: "Action Items" },
          { key: "meet_notes", label: "Notes" }
        ] },
      interview: { def: "Interview", titleKey: "int_interviewee",
        sections: [
          { key: "int_context", label: "Context" },
          { key: "int_questions", label: "Questions" },
          { key: "int_insights", label: "Key Insights" },
          { key: "int_followup", label: "Follow-up" }
        ] },
      pros: { def: "Pros / Cons", titleKey: "pros_subject",
        sections: [
          { key: "pros_pros", label: "Pros" },
          { key: "pros_cons", label: "Cons" },
          { key: "pros_conclusion", label: "Conclusion" }
        ] },
      specification: { def: "Specification Sheet", titleKey: "spec_name",
        sections: [
          { key: "spec_version", label: "Version" },
          { key: "spec_dimensions", label: "Dimensions" },
          { key: "spec_materials", label: "Materials" },
          { key: "spec_properties", label: "Properties" },
          { key: "spec_notes", label: "Notes" }
        ] },
      material: { def: "Material Entry", titleKey: "mat_material",
        sections: [
          { key: "mat_supplier", label: "Supplier" },
          { key: "mat_properties", label: "Properties" },
          { key: "mat_applications", label: "Applications" },
          { key: "mat_notes", label: "Notes" }
        ] },
      reference: { def: "Reference Note", titleKey: "ref_source",
        sections: [
          { key: "ref_summary", label: "Summary" },
          { key: "ref_keyideas", label: "Key Ideas" },
          { key: "ref_quotes", label: "Quotes" },
          { key: "ref_personal", label: "Personal Notes" }
        ] },
      feature: { def: "Feature Request", titleKey: "feat_feature",
        sections: [
          { key: "feat_problem", label: "Problem" },
          { key: "feat_proposal", label: "Proposal" },
          { key: "feat_benefit", label: "Expected Benefit" },
          { key: "feat_notes", label: "Notes" }
        ] },
      changelog: { def: "Changelog Entry", titleKey: "change_version",
        sections: [
          { key: "change_date", label: "Date" },
          { key: "change_added", label: "Added" },
          { key: "change_changed", label: "Changed" },
          { key: "change_fixed", label: "Fixed" },
          { key: "change_notes", label: "Notes" }
        ] }
    };

    var tmpl = T[data.template];
    if (!tmpl) return "# Template Library";

    var out = [];
    var tv = trim(data[tmpl.titleKey]);
    // The heading keeps the template's name and appends your title: "Decision Record: Adopt SQLite".
    var heading = tmpl.def;
    if (tv && !isSkip(tv)) { heading = tmpl.def + ": " + tv; }
    out.push("# " + heading);
    out.push("");

    for (var i = 0; i < tmpl.sections.length; i++) {
      var s = tmpl.sections[i];
      var v = trim(data[s.key]);
      if (isSkip(v)) continue;
      out.push("## " + s.label);
      out.push("");
      out.push(v);
      out.push("");
    }

    return out.join("\\n");
  }
};
"""
