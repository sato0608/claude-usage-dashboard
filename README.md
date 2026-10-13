# Claude 使用履歴ダッシュボード

自分の Claude Code の使用履歴（トークン数・セッション・プロジェクト・モデル別）を、ブラウザで見られるダッシュボードにするツールです。

- 集計はすべて自分のパソコン上で行い、データは外部に送信されません
- Python 3 だけで動きます（追加のライブラリは不要）
- macOS / Windows / Linux で使えます（自動更新の設定だけ macOS 専用）

## 必要なもの

| 必要なもの | 確認方法 |
|---|---|
| Python 3 | ターミナルで `python3 --version`（Windows は `python --version`） |
| Git（ZIP で入手するなら不要） | `git --version` |
| Claude Code を使った記録 | `~/.claude/projects` フォルダがあること |

Python が無い場合は https://www.python.org/downloads/ からインストールしてください。

## インストール

次のどちらかで、このリポジトリを手元に取得します。

**A. git を使う場合**
```bash
git clone https://github.com/sato0608/claude-usage-dashboard.git
cd claude-usage-dashboard
```

**B. ZIP で取得する場合**
1. このページの緑色の **Code** ボタンから **Download ZIP** を選ぶ
2. ダウンロードした ZIP を展開する
3. ターミナルで、展開したフォルダに移動する（`cd` コマンド）

## 実行

フォルダの中で、次を実行します。

```bash
python3 build_usage.py
```
Windows では `python build_usage.py` です。

成功すると、次のように表示されます。

```
3099 件の応答を集計しました → /.../claude-usage-dashboard.html
```

できあがった **`claude-usage-dashboard.html`** をブラウザで開いてください（ダブルクリックで開けます）。

## 最新の状態にする

もう一度 `python3 build_usage.py` を実行して、ブラウザで開き直す（再読み込みする）と、最新になります。

## アプリのように起動する（macOS のみ）

ターミナルを使わず、クリックだけで「最新に集計 → ブラウザで開く」を行えます。

```bash
./make_app.sh
```

`~/Applications/Claude使用履歴.app` が作られます。

1. Finder で `~/Applications` を開く（メニューの「移動」→「ホーム」→ `Applications`）
2. `Claude使用履歴` をダブルクリックして起動する
3. Dock にドラッグしておくと、いつでもワンクリックで起動できる

補足:
- 起動するたびに集計し直すので、常に最新が表示されます。集計に数秒かかります
- フォルダを移動したら、`./make_app.sh` をもう一度実行してください
- 初回起動時に「"Claude使用履歴" がデスクトップ上のフォルダにアクセスしようとしています」と出たら、「許可」を選んでください
- 失敗したときは `~/Library/Logs/claude-usage-dashboard.log` に原因が記録されます
- 「実行できない」と言われたら、先に `chmod +x make_app.sh` を実行してください

## 自動で更新する（macOS のみ）

1 時間ごとに自動で集計したい場合は、フォルダの中で次を実行します。

```bash
./install_launchd.sh
```

「実行できない」と言われたら、先に `chmod +x install_launchd.sh` を実行してください。

自動更新をやめるには:
```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/local.claude-usage-dashboard.plist
rm ~/Library/LaunchAgents/local.claude-usage-dashboard.plist
```

Windows / Linux では、タスクスケジューラや cron で `python3 build_usage.py` を定期実行すると同じことができます。

## うまくいかないとき

| 症状 | 原因と対処 |
|---|---|
| `0 件の応答を集計しました` と出る、またはグラフが空 | Claude Code の記録が見つかっていません。`~/.claude/projects` に `.jsonl` ファイルがあるか確認してください |
| `python3: command not found` | Python が入っていません。インストールするか、`python` で試してください |
| `claude-usage-dashboard.html` が見つからない | `build_usage.py` を実行したフォルダの中にできます。まだ実行していないかもしれません |
| 古い数字のまま | `build_usage.py` をもう一度実行してから、ブラウザで再読み込みしてください |
| グラフの文字が崩れる | 初回は Web フォント（Google Fonts）を読み込みます。オフラインでも表示は可能ですが、フォントが変わります |

## ファイル構成

| ファイル | 役割 |
|---|---|
| `build_usage.py` | ログを集計して、ダッシュボードの HTML を作るスクリプト |
| `template.html` | ダッシュボードの雛形（データは空） |
| `claude-usage-dashboard.html` | **実行すると作られる完成品**（あなたの使用履歴が入る。git の管理外） |
| `make_app.sh` | macOS でクリック起動用の `.app` を作るスクリプト（任意） |
| `install_launchd.sh` | macOS で自動更新を設定するスクリプト（任意） |
| `LICENSE` | MIT ライセンス |

## 注意

- 集計しているのは **Claude Code の使用分だけ**です。claude.ai のチャットは含まれません
- トークン数は、キャッシュから読み込んだ分も含んだ合計です
- 料金は表示していません
- `claude-usage-dashboard.html` にはフォルダ名などの使用履歴が入ります。他の人に渡す・公開するときは、内容を確認してください（`.gitignore` で、誤って commit されないようにしてあります）

## ライセンス

MIT License（[`LICENSE`](LICENSE) を参照）
