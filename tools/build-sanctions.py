"""Derive source-linked fine branches; never infer offences or the currency value of PM."""
from pathlib import Path
import hashlib, json, re

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / 'moonloader/resource/pa26/knowledge-base.json'
pattern = re.compile(r'штраф\s+(?:от\s+)?(\d+)(?:\s+до\s+(\d+))?\s+ПМ', re.I)

def enrich(data):
    count = 0
    for item in data['articles']:
        if item.get('code') != 'AK' or not 20 <= int(item['article']) <= 125:
            continue
        text = item['text']
        assert hashlib.sha256(text.encode()).hexdigest() == item['source_text_sha256']
        matches = list(pattern.finditer(text))
        assert len(matches) == len(re.findall('штраф', text, re.I)), item['id']
        branches = []
        previous_end = text.index('\n') + 1
        for i, match in enumerate(matches, 1):
            start = text.rfind('\n\n', previous_end, match.start()) + 2
            start = max(previous_end, start)
            end = text.find('\n\n', match.end())
            if end < 0:
                end = len(text)
            condition = text[previous_end:start].strip()
            # Keep the complete clause and original consequence, including warnings,
            # disqualification, repeat conditions and alternatives to money.
            excerpt = text[start:end].strip()
            if not condition:
                condition = item['title']
            branches.append({
                'id': f"{item['id']}:fine:{i}", 'kind': 'fine', 'unit': 'ПМ',
                'min': int(match[1]), 'max': int(match[2] or match[1]),
                'condition': condition, 'alternative': excerpt,
                'source_excerpt': excerpt, 'source_text_sha256': item['source_text_sha256'],
            })
            previous_end = end
            count += 1
        item['sanctions'] = branches
    return count

if __name__ == '__main__':
    data = json.loads(PATH.read_text('utf-8-sig'))
    count = enrich(data)
    PATH.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'{count} fine branches, source texts and hashes unchanged; PM currency value unspecified.')
