# Manual defect script

A numbered run-through of the six defects the owner reported, in both
languages, at the minimum window size. It takes under ten minutes per language.

**Nothing here touches your real data.** Every step runs the fixture
composition: a temporary tree of synthetic projects and caches that the launch
creates and owns, a Trash that records instead of moving, a Docker client that
exists only in memory, and in-memory storage.

Record what you actually saw. A line you did not run stays unchecked. If
something differs from what is written here, write down what happened instead —
a wrong expectation in this file is worth more than a checkmark that was never
earned.

---

## Before you start

### Build and launch

```bash
bash scripts/run-fixture.sh --language pt-BR
```

and, for the second pass:

```bash
bash scripts/run-fixture.sh --language en
```

### Why not `build-local.sh`

`scripts/build-local.sh` builds **Release**, and the fixture composition is
`#if DEBUG`: `AppDependencies.fixture(scenario:)`, `PreviewScenario` and all of
`PreviewDependencies.swift` are compiled out of Release, and the Release
configuration does not define `DEBUG`. That is deliberate — a shipping binary
must not be talkable into fixture mode.

The consequence is the trap. Launching the Release product with
`--ui-testing --scenario mixed-results` **does not produce fixtures**. The
arguments are accepted and ignored, and the app runs its real composition
against the folders you configured and against
`~/Library/Application Support/MacDevClean/store.sqlite`.

So: `run-fixture.sh` for verification, `build-local.sh` only for producing an
artifact to install.

### Set the window to the minimum

Drag the bottom-right corner in until the window stops shrinking. It stops at
**1100 × 720**, which is the minimum the app enforces and the size every layout
defect appears at. Several of these steps pass at 1470 pt and fail at 1100.

### Known-broken before you begin

D3 is **not fixed**. The sidebar still empties on some screens. Steps 3 and 5
are written to measure how far it goes, not to confirm a fix. If the sidebar
empties you will have no way to navigate: quit the app and relaunch.

AppKit persists the split view's geometry per app, so a broken layout survives
a relaunch. To start from clean geometry:

```bash
defaults delete dev.macdevclean.app
```

That removes only window position and split sizes. It touches no history, no
settings and no file.

---

## 1 — Counts read as words (D1)

| # | Do this | What must happen | What happened |
|---|---|---|---|
| 1.1 | Look at the "Cache categories" card on Overview, top right | Reads `0 categorias · Zero kB` in Portuguese, `0 categories · Zero kB` in English. **No `^[` anywhere.** | |
| 1.2 | Look at the Caches footer, before selecting anything | `0 itens selecionados` / `0 items selected` | |
| 1.3 | Select one item in Caches | `1 item selecionado` / `1 item selected` — singular in both | |
| 1.4 | Select a second item | `2 itens selecionados` / `2 items selected` — plural in both | |
| 1.5 | Read the sentence under the count in the Caches footer | Portuguese reads "Cerca de … vai para a Lixeira. Isso só libera espaço quando você a esvazia." It must **not** be English when the app is in Portuguese. | |
| 1.6 | Press "Iniciar verificação" on Overview and let it finish | The status line reads "O MacDevClean encontrou N itens em M categorias." with both counts agreeing in number | |
| 1.7 | Scan again and watch the progress line | "Examinando suas pastas. N entradas até agora." — and "1 entrada", singular, if you catch it at one | |

Anything containing `^[` or `](inflect:` is a failure, wherever it appears.

## 2 — Large Files opens its own screen (D2)

| # | Do this | What must happen | What happened |
|---|---|---|---|
| 2.1 | Choose "Arquivos grandes" in the sidebar | The Large Files screen opens: a "Escolher pastas…" button, a smallest-size picker and a sort picker | |
| 2.2 | Read the screen | It must **not** say "Arquivos grandes ainda não foi construído" or anything like it | |
| 2.3 | Press "Escolher pastas…" | The fixture picker returns a folder and a scan runs over synthetic files | |

## 3 — Can you leave the screen? (D3, open)

This is the defect that traps you. It is **not fixed**; this step measures it.

| # | Do this | What must happen | What happened |
|---|---|---|---|
| 3.1 | From Overview, choose "Caches" | The sidebar still lists all six destinations | |
| 3.2 | Choose "Arquivos grandes" | The sidebar still lists all six destinations | |
| 3.3 | Choose "Histórico" | The sidebar still lists all six destinations | |
| 3.4 | Choose "Exclusões" | The sidebar still lists all six destinations | |
| 3.5 | Choose "Ajustes" | The sidebar still lists all six destinations | |
| 3.6 | Whenever the sidebar empties, note **which screen you were on** and whether the column kept its width or collapsed | — | |
| 3.7 | With the sidebar empty, press the sidebar toggle in the toolbar twice | Note whether the rows come back | |

Record 3.6 carefully. The cause is still open and this is the evidence that
narrows it.

## 4 — Caches fits and explains itself (D4)

| # | Do this | What must happen | What happened |
|---|---|---|---|
| 4.1 | Open Caches at the 1100 pt minimum, in Portuguese | All three filter pickers, "Selecionar tudo de risco baixo e médio" and "Limpar seleção" are **inside the window**. They may wrap to a second row. | |
| 4.2 | Check the top and bottom edges | Nothing is cut off above the toolbar or below the footer | |
| 4.3 | Widen the window, then narrow it again | The toolbar moves between one row and two without clipping | |
| 4.4 | On Overview, click a cache category tile, which sends you to Caches with that filter set | If the filter matches nothing, the screen says the filters hide every result and offers "Limpar filtros" — never a blank area | |
| 4.5 | Press "Limpar filtros" | The results come back | |
| 4.6 | Press "Iniciar verificação" on Overview and switch to Caches while it runs | Caches shows a spinner, "Examinando suas pastas. N entradas até agora." and a "Parar verificação" control | |
| 4.7 | Press "Parar verificação" | The scan stops and the screen says so | |

### 4b — The refusal (needs the first-run scenario)

```bash
bash scripts/run-fixture.sh --scenario first-run --language pt-BR
```

| # | Do this | What must happen | What happened |
|---|---|---|---|
| 4.8 | Complete onboarding by adding no folder, if the app lets you reach Caches with none | "Iniciar verificação" is **disabled**, with "O MacDevClean ainda não tem pastas para examinar…" beneath it and a button that opens Ajustes | |
| 4.9 | If onboarding will not let you past without a folder, write that down | That is the better answer, and it means the refusal is unreachable in practice | |

## 5 — History (D5)

| # | Do this | What must happen | What happened |
|---|---|---|---|
| 5.1 | Choose "Histórico" with nothing cleaned yet | "Nenhuma limpeza ainda", readable, with an explanation | |
| 5.2 | Look at "Apagar histórico…" | Disabled | |
| 5.3 | Press "Abrir Lixeira" | Finder opens the Trash. Nothing is emptied. | |
| 5.4 | Note whether the sidebar is present | This is 3.3 again, from the other side | |

## 6 — GitHub (D6)

Nothing to do by hand. `main`, `develop` and `release/1.0.0` are on the remote;
no tag exists and `v1.0.0` must not be created until
[docs/release/checklist.md](../release/checklist.md) passes.

---

## Afterwards

Nothing you did moved a file. To confirm:

```bash
ls -la ~/.Trash | tail -5
```

Nothing from this run should be there. The fixture Trash records and moves
nothing.

Copy your "What happened" column into
[docs/verification/10-defects.md](../verification/10-defects.md), with the
date, the language and the build. An unchecked line stays unchecked.
