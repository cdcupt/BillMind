# BillOwl — Original Beta Feedback (verbatim)

> The users' raw feedback as originally captured, preserved before the shared Google Doc was reformatted into the user-facing update. This is the durable, version-controlled record of what testers reported.
> Evidence images (bug screenshots + example bills + a user bank statement) are kept **local-only** under `feedback/raw/images/` (gitignored — they contain real users' financial data); see `feedback/raw/images/manifest.json` for each image and the line it accompanied. Triaged outcomes: `feedback/BACKLOG.md`.

Captured: 2026-06-22 · Source: feedback Google Doc `1nPe1ds7W4y7bRFwGXBKGTfrAB_gShMrCzwXDSgsUCe8`

---

1. When a user wants to change a journey's name, we must offer a way for them to rename it.

2. A user can click a specific journey and add billing through the old page, right? This is an old achievement. Can we delete it? And, we just support the one way to edit billing: the AI agent from the main page. Here are some reference pictures from users: 

3. When users want to upload pictures to a main page and recognize them through an AI agent, they get an error stating that the picture is too large. I will show you the picture from the users:

4. I'll give you some real example bills from users, and you can test our application using these examples.

5. Some merchandise from London’s theatre, cost 238.40 GBP.

6. A multiple bill order from a wide screenshot. You need to recognize three bill records(WIFI 282.00 RMB, SIM card 99.80 RMB, W London Hotel 10906.42 RMB).

7. A multiple bill order from a wide screenshot. You need to recognize two bill records(xx Airline 26177.00 RMB, Visa center 380.00 RMB).

8. A bill order from a third-party store, cost 373.00 RMB.

9. Some bill invoice from bank, You need to recognize multiple records.

10. We support user input of multiple pictures, sentences, or words in one session. Once the user submits all the information, the AI agent continues to the next step to analyze the input and output the results. During the analysis, we need to delete any repeated records from the user's input, as they might submit the same picture or record multiple times.

