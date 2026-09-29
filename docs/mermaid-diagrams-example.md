# Mermaid Diagrams

MacMD renders fenced `mermaid` code blocks as diagrams in the preview and in HTML and PDF exports. Every diagram follows the active theme. Below is one example of each of the twelve supported types, with its keyword in parentheses.

## Flowchart (`flowchart`)

Steps and decisions, drawn left to right or top to bottom.

```mermaid
flowchart LR
    A([Idea]) --> B[Draft]
    B --> C{Ready?}
    C -->|not yet| D[Revise]
    D --> B
    C -->|yes| E[Publish]
    E --> F[(Archive)]
```

## Sequence (`sequenceDiagram`)

Messages passed between participants over time.

```mermaid
sequenceDiagram
    autonumber
    participant W as Writer
    participant E as Editor
    participant P as Preview
    W->>E: Type markdown
    E->>P: Send changes
    P-->>E: Rendered page
    Note over E,P: Scroll stays in sync
    W->>E: Export
    E-->>W: HTML or PDF
```

## Class (`classDiagram`)

Types, their members, and how they relate.

```mermaid
classDiagram
    class Document {
        +String title
        +String body
        +save()
    }
    class Theme {
        +String name
        +Color background
        +apply()
    }
    class Exporter {
        <<interface>>
        +export(Document) File
    }
    class HTMLExporter
    class PDFExporter
    Document --> Theme : styled by
    Exporter <|.. HTMLExporter
    Exporter <|.. PDFExporter
    Exporter ..> Document : reads
```

## State (`stateDiagram-v2`)

The states something moves through and what moves it.

```mermaid
stateDiagram-v2
    [*] --> Draft
    Draft --> Review : submit
    Review --> Draft : changes requested
    Review --> Published : approve
    Published --> Archived : retire
    Archived --> [*]
```

## Entity Relationship (`erDiagram`)

Records, their fields, and how many of one connect to another.

```mermaid
erDiagram
    AUTHOR ||--o{ POST : writes
    POST ||--|{ SECTION : contains
    POST }o--o{ TAG : "tagged with"
    AUTHOR {
        string name
        string handle
    }
    POST {
        string title
        date published
    }
    SECTION {
        int order
        string heading
    }
```

## Gantt (`gantt`)

Tasks on a calendar, with dependencies and milestones.

```mermaid
gantt
    title Release Plan
    dateFormat YYYY-MM-DD
    axisFormat %b %d
    tickInterval 1week
    weekday monday
    section Design
    Research        :done, des1, 2026-10-01, 5d
    Mockups         :active, des2, after des1, 4d
    section Build
    Editor features :build1, after des2, 8d
    Preview polish  :build2, after des2, 6d
    section Ship
    Testing         :crit, test1, after build1, 4d
    Release         :milestone, rel, after test1, 0d
```

## Pie (`pie`)

Parts of a whole. Slices take their colors from the theme.

```mermaid
pie showData
    title Words per README Section
    "Usage" : 910
    "Setup" : 540
    "Introduction" : 320
    "FAQ" : 230
    "Changelog" : 150
```

## Mindmap (`mindmap`)

Ideas branching out from one center.

```mermaid
mindmap
  root((Markdown))
    Text
      Bold
      Italic
      Links
    Blocks
      Lists
      Tables
      Code
    Extras
      Tasks
      Front matter
      Diagrams
```

## Git Graph (`gitGraph`)

Commits, branches, merges, and tags.

```mermaid
gitGraph
    commit id: "init"
    commit id: "readme"
    branch feature
    checkout feature
    commit id: "add themes"
    commit id: "theme builder"
    checkout main
    commit id: "fix typo"
    merge feature
    commit id: "release" tag: "v2.0.0"
```

## Journey (`journey`)

How a task feels step by step, scored 1 to 5.

```mermaid
journey
    title Writing a README
    section Draft
      Outline sections: 4: Writer
      Write first pass: 3: Writer
    section Polish
      Add screenshots: 2: Writer
      Add diagrams: 5: Writer
    section Ship
      Review: 4: Writer, Reviewer
      Publish: 5: Writer
```

## Timeline (`timeline`)

Events grouped by period.

```mermaid
timeline
    title MacMD Releases
    section June 2026
        1.0 : Native editor : Live highlighting
    section July 2026
        2.0 : Live preview : Mermaid diagrams : HTML export
        2.1 : Pane layouts : PDF export
        2.2 : Auto-hiding toolbar
        2.3 : Theme Builder : Themed diagrams
```

## Quadrant (`quadrantChart`)

Items plotted on two axes and sorted into four quadrants.

```mermaid
quadrantChart
    title Docs Backlog
    x-axis Low Effort --> High Effort
    y-axis Low Impact --> High Impact
    quadrant-1 Plan it
    quadrant-2 Do it now
    quadrant-3 Fill in
    quadrant-4 Skip it
    Fix broken links: [0.15, 0.8]
    Add screenshots: [0.35, 0.7]
    Rewrite intro: [0.6, 0.85]
    Video tour: [0.85, 0.6]
    New logo: [0.75, 0.2]
    Fix typos: [0.2, 0.3]
```
