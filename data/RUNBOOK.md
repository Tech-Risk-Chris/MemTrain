# Runbook for Data Generation

## The base Lemmata

```bash
curl -o data/kilgarriff-bnc-lists-lemma.txt https://www.kilgarriff.co.uk/BNClists/lemma.al
```

## Extracting the Nouns

```bash
grep ' n$' data/kilgarriff-bnc-lists-lemma.txt > data/kilgarriff-noun-lemmata.txt
```

## Generating a new Pool File

```bash
lake exec genpool
```

## Source and attribution

`kilgarriff-bnc-lists-lemma.txt` is the lemmatised word-frequency list for
the British National Corpus (BNC), compiled and published by Adam Kilgarriff:

> Kilgarriff, A. Putting Frequencies in the Dictionary.
> *International Journal of Lexicography* 10 (2) 1997, pp. 135–155.

- List and documentation: <https://www.kilgarriff.co.uk/bnc-readme.html>
- Underlying corpus: the [British National Corpus](http://www.natcorp.ox.ac.uk/),
  administered by the BNC Consortium.

As of this writing, Kilgarriff's page states no explicit license or
redistribution terms for the list itself. It has been freely and openly
served from his site for decades and is widely reused in NLP research and
teaching without restriction, but that is a practical norm, not a confirmed
grant of rights — treat `kilgarriff-bnc-lists-lemma.txt` and
`kilgarriff-noun-lemmata.txt` as third-party data, attributed above, and
outside the scope of this repository's own [LICENSE](../LICENSE), which
covers only the Lean/Lake source.