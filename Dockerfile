
:root {
  /* CATHA logo palette: teal/cyan + warm orange/gold, balanced by deep clinical navy */
  --catha-teal: #08a7c9;
  --catha-cyan: #3ad8e8;
  --catha-blue: #1479b8;
  --catha-navy: #123b59;
  --catha-ink: #17324d;
  --catha-orange: #ff8a1f;
  --catha-gold: #ffbf2f;
  --catha-coral: #ff6a3d;
  --catha-green: #198754;
  --catha-green-soft: #edf7f3;
  --catha-blue-soft: #eef8fb;
  --catha-orange-soft: #fff3e8;
  --catha-purple-soft: #f6efff;
  --catha-border: rgba(16, 47, 69, 0.14);
  --catha-border-strong: rgba(16, 47, 69, 0.24);
  --catha-muted: #647a8b;
  --catha-surface: rgba(255, 255, 255, 0.88);
  --catha-surface-strong: #ffffff;
  --catha-shadow: 0 18px 48px rgba(16, 47, 69, 0.12);
  --catha-shadow-hover: 0 26px 70px rgba(16, 47, 69, 0.18);
  --catha-radius: 22px;
}

/* Overall app shell ------------------------------------------------------- */
html {
  scroll-behavior: smooth;
}

body {
  min-height: 100vh;
  color: var(--catha-ink);
  background:
    radial-gradient(circle at 8% 5%, rgba(18, 199, 213, 0.28) 0, transparent 34%),
    radial-gradient(circle at 94% 3%, rgba(243, 181, 27, 0.32) 0, transparent 31%),
    radial-gradient(circle at 88% 88%, rgba(255, 122, 26, 0.14) 0, transparent 36%),
    linear-gradient(135deg, #eafafb 0%, #f3fbff 32%, #fff6ea 68%, #fff0e0 100%);
  background-attachment: fixed;
  -webkit-font-smoothing: antialiased;
}

.bslib-page-navbar > .container-fluid,
.page-layout,
.container-fluid {
  max-width: 1500px;
}

/* Navbar / brand --------------------------------------------------------- */
.navbar {
  background:
    linear-gradient(105deg, rgba(18, 59, 89, 0.98) 0%, rgba(8, 167, 201, 0.96) 44%, rgba(255, 138, 31, 0.96) 100%) !important;
  box-shadow: 0 16px 46px rgba(16, 47, 69, 0.20);
  border-bottom: 1px solid rgba(255, 255, 255, 0.18);
  padding-top: 0.72rem !important;
  padding-bottom: 0.72rem !important;
  backdrop-filter: blur(12px);
}

.navbar .navbar-brand,
.navbar .nav-link {
  color: rgba(255, 255, 255, 0.88) !important;
}

.navbar .nav-link {
  position: relative;
  border-radius: 999px;
  padding: 0.55rem 0.92rem !important;
  margin: 0 0.08rem;
  font-weight: 700;
  letter-spacing: 0.01em;
  transition: background 180ms ease, color 180ms ease, transform 180ms ease, box-shadow 180ms ease;
}

.navbar .nav-link:hover,
.navbar .nav-link:focus {
  color: #ffffff !important;
  background: rgba(255, 255, 255, 0.15);
  transform: translateY(-1px);
  box-shadow: 0 8px 20px rgba(0, 0, 0, 0.10);
}

.navbar .nav-link.active,
.navbar .nav-item.show .nav-link {
  color: var(--catha-navy) !important;
  background: linear-gradient(135deg, #ffffff 0%, #fff7e8 100%) !important;
  box-shadow: 0 10px 26px rgba(0, 0, 0, 0.16);
}

.catha-brand {
  display: flex;
  align-items: center;
  gap: 0.42rem;
  margin-right: 1rem;
  min-width: 150px;
}

.catha-brand-compact {
  padding: 0.18rem 0.2rem 0.18rem 0;
}

.catha-brand-copy {
  display: flex;
  flex-direction: column;
  line-height: 1.02;
}

.catha-brand-title {
  color: #ffffff;
  font-size: 1.24rem;
  font-weight: 900;
  letter-spacing: 0.09em;
  text-shadow: 0 2px 14px rgba(0, 0, 0, 0.18);
}

.catha-brand small {
  margin-top: 0.16rem;
  color: rgba(255, 255, 255, 0.78);
  font-size: 0.56rem;
  font-weight: 650;
  line-height: 1.15;
  max-width: 185px;
  white-space: normal;
}

/* Page headers ----------------------------------------------------------- */
.lead {
  position: relative;
  margin: 1.15rem 0 1.25rem !important;
  padding: 1.05rem 1.25rem 1.05rem 1.35rem;
  border: 1px solid rgba(255, 255, 255, 0.72);
  border-left: 7px solid var(--catha-orange);
  border-radius: 20px;
  color: var(--catha-navy) !important;
  background:
    linear-gradient(135deg, rgba(255, 255, 255, 0.94) 0%, rgba(228, 248, 252, 0.92) 52%, rgba(255, 243, 225, 0.94) 100%);
  box-shadow: 0 14px 34px rgba(16, 47, 69, 0.08);
  font-size: 1.02rem;
}

/* Cards and feature panels ---------------------------------------------- */
.catha-card,
.card {
  border: 1px solid var(--catha-border) !important;
  border-radius: var(--catha-radius) !important;
  background: var(--catha-surface) !important;
  box-shadow: var(--catha-shadow);
  backdrop-filter: blur(14px);
  overflow: hidden;
  transition: transform 190ms ease, box-shadow 190ms ease, border-color 190ms ease, background 190ms ease;
}

.catha-card:hover,
.card:hover {
  transform: translateY(-2px);
  border-color: rgba(0, 151, 167, 0.34) !important;
  box-shadow: var(--catha-shadow-hover);
  background: rgba(255, 255, 255, 0.95) !important;
}

.card-header {
  position: relative;
  border-bottom: 1px solid rgba(16, 47, 69, 0.10) !important;
  color: var(--catha-navy);
  font-weight: 900;
  letter-spacing: 0.01em;
  background:
    linear-gradient(90deg, rgba(58, 216, 232, 0.22), rgba(255, 138, 31, 0.20)) !important;
  padding: 1rem 1.15rem !important;
}

.card-header::before {
  content: "";
  display: inline-block;
  width: 0.58rem;
  height: 0.58rem;
  margin-right: 0.55rem;
  border-radius: 999px;
  vertical-align: 0.06rem;
  background: linear-gradient(135deg, var(--catha-cyan), var(--catha-orange));
  box-shadow: 0 0 0 4px rgba(18, 199, 213, 0.12);
}

.card-body {
  padding: 1.1rem 1.15rem !important;
}

hr {
  border-color: rgba(16, 47, 69, 0.12);
  opacity: 1;
  margin: 1.15rem 0;
}

.muted-text,
.small.muted-text,
.brush-hint,
.text-muted {
  color: var(--catha-muted) !important;
}

/* Audio / status panels -------------------------------------------------- */
.audio-shell {
  margin-bottom: 1rem;
  padding: 1rem;
  border: 1px solid var(--catha-border);
  border-radius: 18px;
  background:
    linear-gradient(135deg, rgba(255, 255, 255, 0.92), rgba(239, 250, 252, 0.86));
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.75);
}

.status-badge {
  display: inline-flex;
  align-items: center;
  gap: 0.42rem;
  padding: 0.52rem 0.85rem;
  margin-top: 0.6rem;
  border-radius: 999px;
  font-size: 0.9rem;
  font-weight: 800;
  border: 1px solid transparent;
}

.status-badge::before {
  content: "";
  width: 0.55rem;
  height: 0.55rem;
  border-radius: 999px;
  background: currentColor;
  box-shadow: 0 0 0 4px currentColor;
  opacity: 0.35;
}

.status-badge.idle {
  background: rgba(238, 242, 247, 0.94);
  color: #57697b;
  border-color: rgba(87, 105, 123, 0.12);
}

.status-badge.recording {
  background: #ffe8e8;
  color: #b42318;
  border-color: rgba(180, 35, 24, 0.16);
}

.status-badge.ready {
  background: #e9f8ef;
  color: #117a45;
  border-color: rgba(17, 122, 69, 0.16);
}

.status-badge.error {
  background: #fff1f0;
  color: #c52828;
  border-color: rgba(197, 40, 40, 0.16);
}

/* Buttons / execution controls ----------------------------------------- */
.btn {
  position: relative;
  border-radius: 14px !important;
  font-weight: 850 !important;
  letter-spacing: 0.01em;
  border-width: 1px !important;
  transition:
    transform 170ms ease,
    box-shadow 170ms ease,
    background 170ms ease,
    border-color 170ms ease,
    color 170ms ease;
}

.btn:hover,
.btn:focus {
  transform: translateY(-2px);
  box-shadow: 0 14px 30px rgba(16, 47, 69, 0.20);
}

.btn:active {
  transform: translateY(0);
  box-shadow: 0 6px 16px rgba(16, 47, 69, 0.16);
}

.btn-primary,
#run_features,
#add_segment,
#save_annotation {
  color: #ffffff !important;
  border-color: transparent !important;
  background: linear-gradient(135deg, var(--catha-cyan), var(--catha-blue)) !important;
  box-shadow: 0 12px 28px rgba(8, 167, 201, 0.30);
}

.btn-primary:hover,
#run_features:hover,
#add_segment:hover,
#save_annotation:hover {
  background: linear-gradient(135deg, #45ddf0, #0d72ad) !important;
  box-shadow:
    0 18px 38px rgba(0, 151, 167, 0.34),
    0 0 0 4px rgba(18, 199, 213, 0.15);
}

.btn-success,
#start_recording {
  color: #ffffff !important;
  border-color: transparent !important;
  background: linear-gradient(135deg, #18b483, var(--catha-teal)) !important;
  box-shadow: 0 10px 24px rgba(20, 168, 110, 0.22);
}

.btn-success:hover,
#start_recording:hover {
  background: linear-gradient(135deg, #2fd59b, #06a8c7) !important;
  box-shadow:
    0 18px 38px rgba(20, 168, 110, 0.30),
    0 0 0 4px rgba(20, 168, 110, 0.14);
}

.btn-outline-primary,
#run_external_notation,
#download_basic_pitch_midi,
#download_basic_pitch_notes,
#download_basic_pitch_musicxml {
  color: var(--catha-blue) !important;
  border-color: rgba(0, 151, 167, 0.44) !important;
  background:
    linear-gradient(#ffffff, #ffffff) padding-box,
    linear-gradient(135deg, var(--catha-cyan), var(--catha-orange)) border-box !important;
}

.btn-outline-primary:hover,
#run_external_notation:hover,
#download_basic_pitch_midi:hover,
#download_basic_pitch_notes:hover,
#download_basic_pitch_musicxml:hover {
  color: #ffffff !important;
  border-color: transparent !important;
  background: linear-gradient(135deg, var(--catha-blue), var(--catha-orange)) !important;
  box-shadow:
    0 18px 38px rgba(255, 122, 26, 0.25),
    0 0 0 4px rgba(255, 122, 26, 0.12);
}

.btn-outline-danger,
#stop_recording,
#delete_segment {
  color: #bd331d !important;
  border-color: rgba(255, 79, 46, 0.35) !important;
}

.btn-outline-danger:hover,
#stop_recording:hover,
#delete_segment:hover {
  color: #ffffff !important;
  background: linear-gradient(135deg, #ff4f2e, #c92214) !important;
  border-color: transparent !important;
}

.btn-outline-secondary,
#clear_segments,
#reset_audio {
  color: var(--catha-navy) !important;
  border-color: rgba(16, 47, 69, 0.18) !important;
  background: rgba(255, 255, 255, 0.68) !important;
}

.btn-outline-secondary:hover,
#clear_segments:hover,
#reset_audio:hover {
  color: #ffffff !important;
  background: linear-gradient(135deg, var(--catha-navy), #284d68) !important;
  border-color: transparent !important;
}

#run_external_notation,
#run_features,
#add_segment,
#save_annotation,
#download_bundle {
  width: 100%;
  margin-top: 0.35rem;
  padding: 0.72rem 1rem !important;
}

#download_bundle {
  color: #ffffff !important;
  border-color: transparent !important;
  background: linear-gradient(135deg, var(--catha-orange), var(--catha-gold)) !important;
}

#download_bundle:hover {
  box-shadow:
    0 18px 38px rgba(255, 122, 26, 0.32),
    0 0 0 4px rgba(255, 122, 26, 0.14);
}

/* Forms ------------------------------------------------------------------ */
.form-control,
.form-select,
.selectize-input,
input[type="number"],
textarea {
  border-radius: 14px !important;
  border-color: rgba(16, 47, 69, 0.16) !important;
  background: rgba(255, 255, 255, 0.86) !important;
  color: var(--catha-ink) !important;
  transition: border-color 160ms ease, box-shadow 160ms ease, background 160ms ease;
}

.form-control:hover,
.form-select:hover,
.selectize-input:hover,
input[type="number"]:hover,
textarea:hover {
  border-color: rgba(0, 151, 167, 0.34) !important;
}

.form-control:focus,
.form-select:focus,
.selectize-input.focus,
input[type="number"]:focus,
textarea:focus {
  border-color: var(--catha-teal) !important;
  box-shadow: 0 0 0 0.22rem rgba(18, 199, 213, 0.18) !important;
  background: #ffffff !important;
}

.control-label,
.form-label,
label {
  color: var(--catha-navy);
  font-weight: 780;
  margin-bottom: 0.36rem;
}

.irs--shiny .irs-bar,
.irs--shiny .irs-single {
  background: linear-gradient(90deg, var(--catha-teal), var(--catha-orange)) !important;
  border-color: transparent !important;
}

.irs--shiny .irs-handle {
  border-color: var(--catha-teal) !important;
  box-shadow: 0 0 0 4px rgba(18, 199, 213, 0.13);
}

/* Details / advanced panels --------------------------------------------- */
details {
  padding: 0.85rem 0.95rem;
  margin: 0.85rem 0;
  border: 1px solid rgba(0, 151, 167, 0.22);
  border-radius: 18px;
  background:
    linear-gradient(135deg, rgba(238, 248, 251, 0.88), rgba(255, 245, 232, 0.72));
}

details summary {
  cursor: pointer;
  color: var(--catha-navy);
  font-weight: 900;
}

details:hover {
  border-color: rgba(255, 122, 26, 0.38);
  box-shadow: 0 12px 28px rgba(16, 47, 69, 0.08);
}

/* Score rendering panels ------------------------------------------------- */
#paper,
#external_paper {
  background:
    linear-gradient(180deg, #ffffff 0%, #fbfdff 100%) !important;
  padding: 1.1rem !important;
  border-radius: 18px !important;
  margin-top: 1rem !important;
  border: 1px solid rgba(16, 47, 69, 0.14) !important;
  overflow-x: auto !important;
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.9), 0 12px 28px rgba(16, 47, 69, 0.08);
}

#paper:hover,
#external_paper:hover {
  border-color: rgba(0, 151, 167, 0.32) !important;
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.9),
    0 18px 42px rgba(16, 47, 69, 0.13);
}

/* Tables ----------------------------------------------------------------- */
.dataTables_wrapper {
  color: var(--catha-ink);
}

table.dataTable {
  border-collapse: separate !important;
  border-spacing: 0;
  border-radius: 16px;
  overflow: hidden;
}

table.dataTable thead th {
  color: #ffffff;
  background: linear-gradient(135deg, var(--catha-blue), var(--catha-orange));
  border-bottom: none !important;
  font-weight: 850;
}

table.dataTable tbody tr {
  transition: background 130ms ease, transform 130ms ease;
}

table.dataTable tbody tr:hover {
  background: rgba(18, 199, 213, 0.08) !important;
}

.dataTables_wrapper .dataTables_paginate .paginate_button {
  border-radius: 10px !important;
}

.dataTables_wrapper .dataTables_paginate .paginate_button.current,
.dataTables_wrapper .dataTables_paginate .paginate_button.current:hover {
  color: #ffffff !important;
  border: none !important;
  background: linear-gradient(135deg, var(--catha-teal), var(--catha-orange)) !important;
}

/* Tabs ------------------------------------------------------------------- */
.nav-tabs {
  border-bottom: 1px solid rgba(16, 47, 69, 0.12);
}

.nav-tabs .nav-link {
  color: var(--catha-muted);
  font-weight: 800;
  border-radius: 14px 14px 0 0 !important;
  transition: color 150ms ease, background 150ms ease, border-color 150ms ease;
}

.nav-tabs .nav-link:hover {
  color: var(--catha-blue);
  background: rgba(58, 216, 232, 0.12);
  border-color: transparent;
}

.nav-tabs .nav-link.active {
  color: var(--catha-navy);
  border-color: rgba(16, 47, 69, 0.12) rgba(16, 47, 69, 0.12) #ffffff;
  background: #ffffff;
}

/* Layout grids ----------------------------------------------------------- */
.record-grid,
.download-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 0.75rem;
}

.download-grid {
  margin-top: 1rem;
  grid-template-columns: repeat(3, minmax(0, 1fr));
}

.download-grid .btn {
  width: 100%;
}

/* Browser scrollbars where supported ------------------------------------ */
* {
  scrollbar-width: thin;
  scrollbar-color: rgba(0, 151, 167, 0.50) rgba(16, 47, 69, 0.08);
}

::-webkit-scrollbar {
  width: 10px;
  height: 10px;
}

::-webkit-scrollbar-track {
  background: rgba(16, 47, 69, 0.06);
}

::-webkit-scrollbar-thumb {
  background: linear-gradient(180deg, var(--catha-teal), var(--catha-orange));
  border-radius: 999px;
}

/* Responsive refinements ------------------------------------------------- */
@media (max-width: 991px) {
  .record-grid,
  .download-grid {
    grid-template-columns: 1fr;
  }

  .catha-brand {
    min-width: auto;
    margin-right: 0.55rem;
  }

  .catha-brand-title {
    font-size: 1.08rem;
  }

  .catha-brand small {
    max-width: 155px;
    font-size: 0.52rem;
  }

  .lead {
    padding: 0.9rem 1rem;
  }
}

@media (prefers-reduced-motion: reduce) {
  *,
  *::before,
  *::after {
    transition: none !important;
    scroll-behavior: auto !important;
  }

  .btn:hover,
  .card:hover,
  .catha-card:hover,
  .navbar .nav-link:hover {
    transform: none !important;
  }
}


/* Sea-blue / orange accent refinements ----------------------------------- */
.page-layout .card,
.page-layout .catha-card {
  position: relative;
}

.page-layout .card::after,
.page-layout .catha-card::after {
  content: "";
  position: absolute;
  inset: 0 0 auto 0;
  height: 4px;
  background: linear-gradient(90deg, var(--catha-cyan), var(--catha-blue) 48%, var(--catha-orange));
  opacity: 0.92;
}

.navbar .navbar-brand {
  font-weight: 900;
}

.lead::after {
  content: "";
  position: absolute;
  right: 16px;
  top: 14px;
  width: 74px;
  height: 74px;
  border-radius: 999px;
  background: radial-gradient(circle, rgba(58,216,232,0.20) 0%, rgba(255,138,31,0.10) 58%, transparent 72%);
  pointer-events: none;
}

.btn,
.navbar .nav-link,
.form-control,
.form-select,
.selectize-input,
#paper,
#external_paper,
details,
table.dataTable {
  will-change: transform;
}

#run_features,
#run_external_notation,
#download_bundle {
  letter-spacing: 0.015em;
}

#run_features,
#run_external_notation,
#download_bundle,
#add_segment,
#save_annotation,
#start_recording,
#stop_recording {
  position: relative;
  overflow: hidden;
}

#run_features::before,
#run_external_notation::before,
#download_bundle::before,
#add_segment::before,
#save_annotation::before,
#start_recording::before,
#stop_recording::before {
  content: "";
  position: absolute;
  top: 0;
  left: -120%;
  width: 50%;
  height: 100%;
  background: linear-gradient(90deg, transparent, rgba(255,255,255,0.32), transparent);
  transition: left 300ms ease;
}

#run_features:hover::before,
#run_external_notation:hover::before,
#download_bundle:hover::before,
#add_segment:hover::before,
#save_annotation:hover::before,
#start_recording:hover::before,
#stop_recording:hover::before {
  left: 130%;
}

.status-badge.idle {
  background: linear-gradient(135deg, rgba(234,247,252,0.95), rgba(255,244,231,0.92));
  color: var(--catha-navy);
}

.status-badge.ready {
  background: linear-gradient(135deg, rgba(231,249,241,0.96), rgba(231,250,252,0.96));
}

.status-badge.error {
  background: linear-gradient(135deg, rgba(255,241,240,0.97), rgba(255,246,232,0.96));
}

.nav-tabs .nav-link.active {
  border-top: 3px solid var(--catha-orange);
  box-shadow: 0 -2px 0 rgba(58,216,232,0.12) inset;
}

.audio-shell {
  border-left: 4px solid rgba(8, 167, 201, 0.35);
}

.download-grid .btn {
  min-height: 52px;
}
