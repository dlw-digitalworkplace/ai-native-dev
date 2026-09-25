# AIND writing guide

Follow this guide for **all text a human reads**:

- work-item comments,
- PR bodies, review threads and replies,
- plan files and research findings,
- your own messages in the console.

People review this text quickly, and many read English as a second language. Write so they can
understand it on the first read.

## Core rules (every level)

1. **Lead with the ask.** If a human must decide or do something, start with
   `**What I need from you:**` and a numbered list. Make each item a yes/no or pick-one question.
   If nothing is needed, say so in one line.
2. **One idea per sentence.** Split a long sentence instead of adding commas, "which" or "while".
3. **Structure over prose.** Use headings, bullets and tables. Keep paragraphs to 3 sentences or fewer.
4. **Use common words.** Write "use", not "leverage". Write "check", not "ascertain". Write "because",
   not "due to the fact that".
5. **Explain jargon once.** If you need a technical term the reader may not know, explain it in
   plain words the first time you use it.
6. **Be direct.** Remove filler and hedging: "it's worth noting", "potentially", "in order to",
   "it should be mentioned that". State what you know. Say clearly what you don't know.
7. **Separate facts from guesses.** Label them `Found:` (seen in the code, story or docs) and
   `Assumed:` (your guess, needs confirmation).
8. **Be concrete.** Name the file, field, screen or value. Do not write "some parts" or "various
   components".
9. **Keep it short.** Cut every sentence that does not help the reader decide or act.

## Console messages

- Keep progress notes to one or two lines.
- End every phase with this block. Keep each line short:

  ```
  **Done:** <what this run did, one line>
  **Needs you:** <what the human must do now, or "nothing">
  **Next:** <the next command or step>
  ```

## Reading level

Use the row for the active level shown at the top of this output.

| Level | Max sentence length | Jargon | Target reader |
|---|---|---|---|
| `plain` | about 15 words | none unexplained; prefer everyday words | mixed or non-technical readers, English as a second language (B1–B2) |
| `standard` | about 20 words | explain terms outside the team's domain | a delivery team with testers and analysts (B2) |
| `technical` | about 25 words | domain and code terms allowed without explanation | developers only |

At every level, the core rules still apply.

## Technical documents

Plans, PR bodies and review findings follow these rules too. A human reads and approves them,
even when a coding agent acts on them afterwards.

- **Precision comes from exact names, not from complex sentences.** Put files, functions, fields,
  tokens and values in backticks. Explain everything around them in plain sentences.
- **Say why, then what.** Start a section with one plain sentence on its purpose. Put the detail
  after it.
- **Explain each technical choice in one plain sentence** a non-developer reviewer can follow,
  e.g. "This keeps all colors in one place, so no screen needs its own change."

## Language

Always write in **English**, whatever language the story, the codebase or the person talking to
you uses.
