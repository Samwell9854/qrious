# What readers do with Qrious's codes

The specs say what a payload means; a reader decides what to do with it, and readers differ. This page records what has been tested on real readers, payload by payload, so that a decision resting on a reader's behaviour can be checked against what was actually seen, and tested again when the reader changes.

Only first-party readers count here: the camera app a phone ships with, which is what most people scan with. Web-based readers and third-party apps disagree with each other and with the phones, so a result from one of them says nothing about the next.

What is recorded so far comes from the **iPhone camera app**. Android's own reader has not been tested; when it is, its results go beside these, not in place of them.

## iPhone camera app

Tested on iOS 27.2.1, 2026-11-25, by scanning codes from a screen and reading what Contacts offers to save.

### MeCard `N:`

DoCoMo's spec defines `N:` as the last name, a comma, then the first name, and says nothing about a value with no comma. The iPhone does more than that: it fills Contacts' prefix, first, middle, last and suffix fields, guessing at the parts. `␣` marks a space and `⍽` a non-breaking space. Each table runs from the simplest name to the longest.

Every result below fits three rules:

1. **The comma counts only when text follows it.** Then the text before it is the last name, exactly as written, even empty, and the text after it holds the given names: an optional title, a first name and at most one middle name. With the last name empty, the middle name moves to the last name.
2. **Otherwise the whole value is a name written out**: an optional title, a first name, a middle name, a last name (particles such as *de la* kept with it) and an optional suffix. A comma with nothing after it stays in the name.
3. **Three names at most**, first, middle and last, besides a title and a suffix. One more and the whole name is lost, whichever way it is written; with nothing else on the card, the code is not read at all.

A non-breaking space counts as a space throughout, and alone it counts as nothing.

**A name on both sides of the comma** (rule 1).

| Payload | Prefix | First | Middle | Last | Suffix |
| --- | --- | --- | --- | --- | --- |
| `N:Lovelace,Ada` | | Ada | | Lovelace | |
| `N:Lovelace,␣Ada` | | Ada | | Lovelace | |
| `N:Lovelace,Ada␣Mary` | | Ada | Mary | Lovelace | |
| `N:Cruz,Mary⍽Ann` | | Mary | Ann | Cruz | |
| `N:Smith,John␣Paul-George` | | John | Paul-George | Smith | |
| `N:Lovelace,Ada␣Jr.` | | Ada | Jr. | Lovelace | |
| `N:Lovelace,Dr.␣Ada` | Dr. | Ada | | Lovelace | |
| `N:Smith,Dr.␣John␣Paul` | Dr. | John | Paul | Smith | |
| `N:Lovelace␣Jr.,Ada` | | Ada | | Lovelace Jr. | |
| `N:Smith␣Jones,John␣Paul` | | John | Paul | Smith Jones | |
| `N:de␣la␣Cruz,Mary␣Ann` | | Mary | Ann | de la Cruz | |

**Nothing before the comma** (rule 1, the middle name moved to the last).

| Payload | Prefix | First | Middle | Last | Suffix |
| --- | --- | --- | --- | --- | --- |
| `N:,Ada` | | Ada | | | |
| `N:,Mary␣Ann` | | Mary | | Ann | |

**No comma, or nothing after it** (rule 2).

| Payload | Prefix | First | Middle | Last | Suffix |
| --- | --- | --- | --- | --- | --- |
| `N:Ada` | | Ada | | | |
| `N:Lovelace` | | Lovelace | | | |
| `N:␣Lovelace` | | ␣Lovelace | | | |
| `N:Lovelace,` | | Lovelace, | | | |
| `N:Lovelace,,` | | Lovelace,, | | | |
| `N:Lovelace,␣` | | Lovelace,␣ | | | |
| `N:Lovelace,⍽` | | Lovelace,␣ | | | |
| `N:Mary␣Ann` | | Mary | | Ann | |
| `N:Mary⍽Ann` | | Mary | | Ann | |
| `N:John␣Paul␣George` | | John | Paul | George | |
| `N:John␣Smith␣Jones` | | John | Smith | Jones | |
| `N:Mary␣Ann␣de␣la␣Cruz` | | Mary | Ann | de la Cruz | |
| `N:Dr.␣Ada␣Lovelace␣Jr.` | Dr. | Ada | | Lovelace | Jr. |

**More than three names** (rule 3): the name is lost.

| Payload | Result |
| --- | --- |
| `N:,John␣Paul␣George` | not read: "No usable data found" |
| `N:Lovelace,Ada␣Mary␣Byron` | not read |
| `N:Smith,John␣Paul␣George` | not read |
| `N:Smith,J.␣P.␣George` | not read |
| `N:John␣Paul␣George␣Smith` | not read |
| `N:Smith,John␣Paul␣George;TEL:5550000` | the phone number only, no name |
| `N:Lovelace,Dr.␣Ada␣Mary␣Jr.` | the prefix Dr. only |
| `N:Dr.␣John␣Paul␣George␣Smith␣Jr.` | the prefix Dr. and the suffix Jr. only |

**What cannot be written.** A MeCard cannot give the iPhone:

- **a last name alone**: every form of it becomes the first name. Qrious writes it bare, which leaves no stray comma ([formats.md](formats.md#supported-formats));
- **a first name of two words or more, whole**: the second word becomes the middle name, or the last name with no comma;
- **a suffix with a comma**: after the comma it is taken for a middle name, before it it stays in the last name;
- **more than three names**, counting a last name and the given names: the name is lost, in either form, and with nothing else on the card the code is not read at all.

A vCard has none of these limits: `N:Smith;John␣Paul␣George;;;` gives first *John Paul George*, last Smith.

Follow-up: [#25](https://github.com/Samwell9854/qrious/issues/25).
