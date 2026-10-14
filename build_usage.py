#!/usr/bin/env python3
"""Claude Code のローカルログ (~/.claude/projects/**/*.jsonl) を集計し、
テンプレート (template.html) の /*DATA*/ ... /*END*/ の間に埋め込み、
claude-usage-dashboard.html として書き出す。

使い方: python3 build_usage.py
"""
import collections, datetime as dt, glob, json, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
TEMPLATE = os.path.join(HERE, 'template.html')
HTML = os.path.join(HERE, 'claude-usage-dashboard.html')
LOGS = os.path.expanduser('~/.claude/projects')

MODEL_NAMES = {
    'claude-opus-5-5': 'Opus 5.5', 'claude-opus-5': 'Opus 5',
    'claude-sonnet-5-5': 'Sonnet 5.5', 'claude-sonnet-5': 'Sonnet 5',
    'claude-haiku-5-5': 'Haiku 5.5', 'claude-fable-5-1': 'Fable 5.1',
}

def model_name(m):
    return MODEL_NAMES.get(m) or re.sub(r'^claude-', '', m or '不明')

def project_name(cwd):
    if not cwd:
        return '不明'
    m = re.search(r'scratch-(\d{4})-(\d{2})-(\d{2})', cwd)
    if m:
        return f'フォルダなし ({int(m[2])}/{int(m[3])})'
    if cwd.rstrip('/') == os.path.expanduser('~'):
        return 'ホーム'
    return os.path.basename(cwd.rstrip('/'))


def collect():
    seen, rows = set(), []
    for f in glob.glob(os.path.join(LOGS, '**', '*.jsonl'), recursive=True):
        with open(f, errors='ignore') as fh:
            for line in fh:
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                if d.get('type') != 'assistant':
                    continue
                m = d.get('message') or {}
                u = m.get('usage')
                if not u or m.get('model') == '<synthetic>':
                    continue
                key = (m.get('id'), d.get('requestId'))
                if key in seen:
                    continue
                seen.add(key)
                ts = dt.datetime.fromisoformat(d['timestamp'].replace('Z', '+00:00')).astimezone()
                inp = u.get('input_tokens', 0) + u.get('cache_read_input_tokens', 0) + u.get('cache_creation_input_tokens', 0)
                rows.append(dict(ts=ts, day=ts.date(), model=model_name(m.get('model')),
                                 project=project_name(d.get('cwd')), session=d.get('sessionId'),
                                 inp=inp, out=u.get('output_tokens', 0)))
    return rows


def build(rows):
    today = dt.date.today()
    start = min(r['day'] for r in rows)
    days = [start + dt.timedelta(i) for i in range((today - start).days + 1)]
    by_day = {d: dict(t=0, o=0, r=0, s=set()) for d in days}
    for r in rows:
        b = by_day[r['day']]
        b['t'] += r['inp'] + r['out']; b['o'] += r['out']; b['r'] += 1; b['s'].add(r['session'])
    daily = [dict(d=d.isoformat(), t=by_day[d]['t'], o=by_day[d]['o'], r=by_day[d]['r'], s=len(by_day[d]['s'])) for d in days]

    def window(a, b):  # days ago, inclusive range [today-a, today-b]
        lo, hi = today - dt.timedelta(a), today - dt.timedelta(b)
        sel = [r for r in rows if lo <= r['day'] <= hi]
        return dict(t=sum(r['inp'] + r['out'] for r in sel), o=sum(r['out'] for r in sel),
                    r=len(sel), s=len({r['session'] for r in sel}))
    # 期間ごとの指標。キーは日数（0 は全期間）。n 日 = 今日を含む直近 n 日と、その前の n 日との比較
    def kpi_set(n):
        if n:
            cur, prev = window(n - 1, 0), window(2 * n - 1, n)
            spark_days = daily[-max(28, n):]
        else:
            cur, prev = window((today - start).days, 0), None
            spark_days = daily
        out = []
        for key, label, fmt in [('t', 'トークン合計', 'tok'), ('o', '出力トークン', 'tok'),
                                ('s', 'セッション数', 'int'), ('r', '応答数', 'int')]:
            delta = None if not prev or not prev[key] else round((cur[key] / prev[key] - 1) * 100, 1)
            out.append(dict(label=label, value=cur[key], fmt=fmt, delta=delta,
                            spark=[x[key] for x in spark_days]))
        return out
    kpi_sets = {str(n): kpi_set(n) for n in (1, 7, 30, 90, 0)}
    kpis = kpi_sets['7']  # 古いテンプレートとの互換用

    # 今日の時間帯別（0〜23 時）の使用量
    hourly = [dict(h=h, t=0, r=0) for h in range(24)]
    for r in rows:
        if r['day'] == today:
            hourly[r['ts'].hour]['t'] += r['inp'] + r['out']; hourly[r['ts'].hour]['r'] += 1

    weeks = collections.OrderedDict()
    for x in daily:
        d = dt.date.fromisoformat(x['d'])
        mon = d - dt.timedelta(d.weekday())
        w = weeks.setdefault(mon, dict(label=f'{mon.month}/{mon.day}', r=0, t=0))
        w['r'] += x['r']; w['t'] += x['t']

    proj = collections.defaultdict(lambda: dict(t=0, s=set(), last=None, models=collections.Counter()))
    for r in rows:
        p = proj[r['project']]
        p['t'] += r['inp'] + r['out']; p['s'].add(r['session'])
        p['last'] = max(p['last'] or r['day'], r['day']); p['models'][r['model']] += r['inp'] + r['out']
    projects = sorted(({'name': k, 't': v['t'], 's': len(v['s']), 'last': v['last'].isoformat(),
                        'model': v['models'].most_common(1)[0][0]} for k, v in proj.items()),
                      key=lambda p: -p['t'])

    mod = collections.defaultdict(lambda: dict(t=0, r=0))
    for r in rows:
        mod[r['model']]['t'] += r['inp'] + r['out']; mod[r['model']]['r'] += 1
    total = sum(v['t'] for v in mod.values()) or 1
    models = sorted(({'name': k, 't': v['t'], 'r': v['r'], 'share': v['t'] / total} for k, v in mod.items()),
                    key=lambda m: -m['t'])

    ses = collections.defaultdict(lambda: dict(t=0, o=0, r=0, start=None, end=None, models=collections.Counter(), project=None))
    for r in rows:
        x = ses[r['session']]
        x['t'] += r['inp'] + r['out']; x['o'] += r['out']; x['r'] += 1; x['project'] = r['project']
        x['start'] = min(x['start'] or r['ts'], r['ts']); x['end'] = max(x['end'] or r['ts'], r['ts'])
        x['models'][r['model']] += r['inp'] + r['out']
    sessions = sorted(({'sid': k, 'start': v['start'].strftime('%Y-%m-%d %H:%M'), 'min': round((v['end'] - v['start']).total_seconds() / 60),
                        'project': v['project'], 'model': v['models'].most_common(1)[0][0], 'r': v['r'], 't': v['t'], 'o': v['o']}
                       for k, v in ses.items()), key=lambda x: x['start'], reverse=True)
    sid_index = {s['sid']: i for i, s in enumerate(sessions)}
    for s in sessions:
        del s['sid']

    # 期間で絞り込むための内訳（日 × セッション × フォルダ × モデル）。i は sessions の添字
    cell = collections.defaultdict(lambda: dict(t=0, o=0, r=0))
    for r in rows:
        c = cell[(r['day'], sid_index[r['session']], r['project'], r['model'])]
        c['t'] += r['inp'] + r['out']; c['o'] += r['out']; c['r'] += 1
    dpm = [dict(d=k[0].isoformat(), i=k[1], p=k[2], m=k[3], t=v['t'], o=v['o'], r=v['r'])
           for k, v in sorted(cell.items(), key=lambda kv: (kv[0][0], kv[0][1], kv[0][2], kv[0][3]))]
    for m_ in models:
        m_['avg'] = round(m_['t'] / m_['r']) if m_['r'] else 0

    return dict(sessions=sessions, generated=dt.datetime.now().strftime('%Y-%m-%d %H:%M'), start=start.isoformat(), end=today.isoformat(),
                totals=dict(t=sum(r['inp'] + r['out'] for r in rows), r=len(rows), s=len({r['session'] for r in rows})),
                daily=daily, hourly=hourly, dpm=dpm, kpis=kpis, kpi_sets=kpi_sets, weeks=list(weeks.values()), projects=projects, models=models)


if __name__ == '__main__':
    rows = collect()
    data = build(rows) if rows else None
    html = open(TEMPLATE, encoding='utf-8').read()
    html = re.sub(r'/\*DATA\*/.*?/\*END\*/', lambda _: '/*DATA*/' + json.dumps(data, ensure_ascii=False) + '/*END*/', html, flags=re.S)
    open(HTML, 'w', encoding='utf-8').write(html)
    print(f'{len(rows)} 件の応答を集計しました → {HTML}')
