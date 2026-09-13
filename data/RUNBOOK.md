# Runbook for Data Generation

## The base Lemmata

```bash
curl -o data/kilgariff-bnc-lists-lemma.txt https://www.kilgarriff.co.uk/BNClists/lemma.al
```

## Extracting the Nouns

```bash
grep ' n$' data/kilgarriff-bnc-lists-lemma.txt > data/kilgarriff-noun-lemmata.txt
```