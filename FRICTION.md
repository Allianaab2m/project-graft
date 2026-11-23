# 摩擦ログ

Graft を書いていて、言語・std・ツール・Brix が邪魔をした箇所の記録．1件ごとに「やりたかったこと」「実際に書いたコード」「本来書きたかった形」「行き先」を書く．

行き先は次のどれか．

- 本体 issue: 不具合や実装の不足
- proposal: 仕様を変える必要がある
- Brix: Brix への要望
- 我慢: 設計上の判断として受け入れる

本体へ出すのは、Graft 以外のプログラムでも困ると言えるものだけ．

## 言語

### L1. enum のバリアントをまとめて import できない

やりたかったこと: lexer とテストで `Token.Kind` の全バリアント（70個）を使う．

実際に書いたコード:

```emel
import Token.{
  Kind,
  Token,
  Whitespace,
  Newline,
  # ... 70 行続く
}
```

型名で修飾する `Kind.Whitespace` は書けない（`.` の左は module か Trait だけ）．全部を import する記法もない（`[module.import]`）．parser、fmt、型検査と、Kind を使うモジュールが増えるたびに同じ列挙を書くことになる．

本来の形: `Kind.Whitespace` と型名で修飾して書く．または `import Token.Kind.{..}` でバリアントだけまとめて入れる．

行き先: proposal．構文木のノード種別や診断コードのように、バリアントの多い enum を複数のモジュールで使うプログラムなら同じ問題が起きる．

### L2. 文字のリテラルがない

やりたかったこと: lexer で `"` や `{` と比べる．

実際に書いたコード: 文字コードの const を 29 個並べた．

```emel
const QUOTE = 0x22
const L_BRACE = 0x7B
```

`"e"` や `"x"` のように一度しか使わない文字は、`0x65` や `0x78` のまま式に残っている．

本来の形: パターンにも書ける、コードポイントの Int になるリテラル．Char 型を足さないのは仕様の判断（`[lex.literal]`）なので、型は Int のままでよい．

行き先: proposal を検討．ただし文字列のコードポイントを走査するプログラムが Graft 以外にどれだけあるかを先に確かめる．

### L3. 同じ effect を書く `uses` 節を 190 回書いた

やりたかったこと: parser の状態を `State[Parser]` に持ち、文法の関数から読み書きする．

実際に書いたコード: 文法の関数すべてに同じ節を付けた．`src/` 全体で 190 回．

```emel
fn param_list() -> () uses { State[Parser] } {
fn arm_list() -> () uses { State[Parser] } {
fn with_items() -> () uses { State[Parser] } {
```

効果の集合に名前を付ける手段がない．関数を引数に取る箇所（`delimited` や `separated_items`）は型にも同じ節が入るので、シグネチャが1行に収まらず引数を折り返している．

本来の形: effect の集合の別名（`effects ParserEffects = { State[Parser] }` のようなもの）．またはモジュール単位で既定の `uses` を宣言する．

行き先: proposal．State で手続き的なアルゴリズムを書くプログラムなら、関数の数だけ同じ節が並ぶ．

### L4. パターンの or がない

やりたかったこと: 二項演算子の結合力を種別ごとに返す．

実際に書いたコード: 比較演算子 6 つを1行ずつ書いた．`infix_power` は 15 本の arm になった．

```emel
Eq2     -> 4
Neq     -> 4
Lt      -> 4
LtEq    -> 4
Gt      -> 4
GtEq    -> 4
```

arm を並べられない条件（`at_pattern_start` など）は `kind == A || kind == B || ...` の連鎖にした．

本来の形: `Eq2 | Neq | Lt | LtEq | Gt | GtEq -> 4`．

行き先: proposal．

### L5. 値を捨てて `()` にする書き方がない

やりたかったこと: `if at(LBrace) { block() } else { expect(LBrace) }` のように、値を返す関数を副作用のためだけに呼ぶ．

実際に書いたコード: ブロックの最後に `()` を足した．`src/grammar.emel` だけで 27 か所．

```emel
if at(LParen) {
  arg_list()
} else {
  expect(LParen)
  ()
}
```

`else` のない `if` の本体や、`()` を返す関数の最後の式が値を持つと型エラー（E0301）になる．文の途中なら値は黙って捨てられるので、最後の式だけ扱いが違う．Rust は `;` で捨てられる．

本来の形: 文の位置と同じく、`()` が期待される最後の式の値も捨てる．または値を捨てる組み込み（`ignore(expect(LParen))`）．

行き先: proposal を検討．書き忘れても型エラーで気づけるので、優先度は低い．

### L6. ループがないので、Rust の文法関数 94 個が 152 個になった

やりたかったこと: Rust の `while` と `loop` を移植する．

実際に書いたコード: ループごとに末尾呼び出しの補助関数を作った（`delimited_elements`、`block_items`、`skip_line` など）．ループの中で更新していた変数（`count`、`trailing_comma`、`seen_rest`）は引数と戻り値のタプルに移した．

```emel
fn paren_elements(count: Int) -> (Int, Bool) uses { State[Parser] } {
  if at(RParen) || at_eof() {
    (count, count > 0)
  } else {
    expr()
    if eat(Comma) { paren_elements(count + 1) } else { (count + 1, False) }
  }
}
```

行き先: 我慢．ループを持たないのは言語の判断で、末尾呼び出しは保証されている．

その後、引数を素通しするだけの補助関数（`delimited_elements(close, element)` など）は、ローカル fn（`[fn.local]`）にして呼び出し元の中に置いた．ローカル fn は外側の変数を捕捉し、自分への末尾呼び出しも保証されるので、素通しの引数が消える．ただし捕捉した関数引数を呼ぶと L7 に当たる．補助関数どうしが呼び合う lexer は、ローカル fn が相互再帰できないので移せない．

### L7. 引数の関数型が、書いていない fails と uses について多相になる

やりたかったこと: `fn update(f: fn(Parser) -> Parser)` で受け取った関数を `State.update` に渡す．

起きたこと: `State.update` は純粋な関数を求めるので、E0321（`expected fails {}, found fails E(f)`）と E0403 になった．引数の型に節を書かないと、その関数はどんな error と effect も持ちうる扱いになる．

対応: `st.set(f(st.get()))` と書き換えた．

その後、fmt の `Doc.column(f)` で同じ形に当たり、引数の型に `fails {} uses {}` と書けば純粋な関数だけを受け取れることがわかった．

```emel
pub fn column(f: fn(Int) -> Doc fails {} uses {}) -> Doc {
  Column(f)
}
```

型のフィールドに書いた `fn(Int) -> Doc` は純粋な関数の意味になり、引数に書いた同じ型は多相になる．同じ字面で意味が違うので、E0321 を見ても原因に気づきにくい．

ローカル fn でも同じことが起きる．外側の関数の引数 `element: fn() -> () uses { State[Parser] }` を、シグネチャを書いたローカル fn の中で呼ぶと E0318（`unhandled error E(element)`）になる．引数の型に `fails {}` と書いて直した．

本来の形: E0321、E0403、E0318 の help で `fails {} uses {}` を書くよう示す．

行き先: 本体 issue（診断の help）を検討．

### L8. モジュールで修飾して定数を参照できない

やりたかったこと: `main` から `Format.DEFAULT_WIDTH` を参照する．

起きたこと: `.` の後ろには小文字の名前か型名しか書けず、E0110（`expected lower name`）になった．関数は `Format.format(text)` と書けるのに、定数は import しないと使えない．

```emel
import Format.{DEFAULT_WIDTH, Done, SyntaxErrors, Internal}
```

行き先: proposal．L1 と同じく、名前の種類によって修飾できるかが変わる．

M3 の `src/check.emel` でも、`Modules.CORE`（core モジュールの表）と書いて同じエラーになり、import に直した．

### L9. 関数名と、同じモジュールの型のフィールド名が衝突する

やりたかったこと: 構文木のノード型 `Node(children: ...)` と、ノードだけを返す関数 `children(node)` を同じモジュールに置く．

起きたこと: E0334（`function children has the same name as a field of Node`）になった．フィールドを `trees` と `outer` に、printer の関数を `trailing_of`、`target_width`、`is_pending` に改名した．

仕様を読み直したら、5.3 に明記されていた．型を定義したモジュールの関数は `user.f(...)` とメソッドのように呼べる（`[type.rules]`）ので、フィールドと同じ名前の関数は書けない．

行き先: 我慢（仕様どおり）．

## std

### S1. String を位置で読めない

やりたかったこと: ソースを先頭から1文字ずつ読み、トークンの範囲を切り出す．

実際に書いたコード: ソース全体を `Array[Int]`（コードポイント）に変換して走査し、切り出すときに文字列へ戻している．

```emel
src = Array.from_list(String.code_points(text))

pub fn slice(src: Array[Int], start: Int, end: Int) -> String {
  Array.slice(src, start, end)
    |> Array.to_list
    |> List.filter_map(String.from_code_point)
    |> String.concat
}
```

`String` には位置を指定して読む関数も部分文字列を取る関数もない（`[api.string]`）．コードポイントの列から文字列に戻す関数もないので、1文字ずつ `from_code_point` してから連結している．予約語の判定は `match` で文字列と比べたいので、名前のトークンごとにこの変換が走る．

本来の形: `String.from_code_points(List[Int]) -> String`．または位置をバイトかコードポイントで指定する `String.slice`．

行き先: 本体 issue（std への追加）．パーサーやテンプレート処理など、文字列を走査するプログラム全般で必要になる．

## ツール

### T1. wasm で FileSystem を使うプログラムがコンパイルに通る

やりたかったこと: corpus の round-trip を3ターゲットで走らせる．

起きたこと: `--target wasm` でもビルドは通り、実行すると `read_text` が全件失敗した（`0/303 files round-trip`）．wasm に `Std.FileSystem` がないことは仕様に書いてある（`[target.wasm]`）が、実行するまで気づけない．

本来の形: wasm で使えない handler に届くプログラムは、ビルド時に診断が出る．

行き先: 本体 issue．失敗したときの error の中身はまだ確かめていない（Graft 側で `escape { _ -> None }` していて見えない）．

### T2. reference の parser が、壊れた handler の `init` で panic する

起きたこと: Graft と reference の構文木を、corpus を壊した入力 4,400 件で突き合わせたら、reference が 6 件 panic した．どれも同じ箇所．

```emel
handler Hd: Kv {
  init(a
}
```

`emela check` も `expected to be at L_BRACE, found R_BRACE`（`parser.rs:219`）で落ちる．`handler_decl` が `init` の引数リストを読んだ後、`{` があるか確かめずに `block` を呼び、`block` は `{` を前提に `bump_kind(L_BRACE)` する．main のコードも同じ．入力途中の `init(a` で落ちるので、エディタの language server も落ちる．

本来の形: `{` がなければ診断を出して読み進める（`block_or_error` と同じ扱い）．

行き先: 本体 issue（未提出）．Graft は reference の木に合わせる都合で、同じ箇所を検査なしで読んでいる．

### T3. `emela fmt` が、`||` の連鎖をちょうど幅いっぱいに折り返すと internal error になる

起きたこと: Graft の fmt を reference と幅を変えて突き合わせたら、reference の出力が構文エラーになって internal error を返す入力が見つかった．既定の幅 100 でも、次の正しいプログラムで起きる（`a` は 84 個か 85 個）．

```emel
fn f(x: Bool) -> Int {
  if x || aaaa…aaaa || x {
    1
  } else {
    2
  }
}
```

```console
$ emela fmt --check or84.emel
error: internal error: cannot format this file: the output has a syntax error: expected `{` at 29..30
```

`||` の連鎖が括弧の外で折り返すときは括弧で包む規則（`[fmt.wrap]`）がある．包むかどうかは、連鎖だけを描画してみて行頭が `||` になるかで決めている（`or_chain_in_parens`）．この試し描きには、条件の後ろに続く ` {` が入っていない．連鎖だけなら幅に収まり、` {` まで含めると収まらない長さのとき、括弧なしで折り返して、行頭の `||` が無名関数として読まれる．main（a9d27cf）でも同じ．

本来の形: 試し描きに後続の幅を含めるか、実際に折り返したかで決める．

行き先: 本体 issue（未提出）．Graft は reference に合わせて同じ出力を作り、同じく internal error にしている．

その後、Graft 自身の `src/validation.emel` で踏んだ．`if kind == UnderscoreExpr || kind == PathExpr || kind == UnitExpr || kind == Literal {` がちょうどこの長さで、CI の `emela fmt --check` が internal error で落ちた．手元では `emela fmt .` の出力を捨てていて気づかなかった．条件を `[UnderscoreExpr, PathExpr, UnitExpr, Literal].any(|k| k == kind)` に書き換えて避けた．

### T4. native で `String.chars` と `String.length` が使えない

起きたこと: 行末の `\r` を落とすのに `String.concat(s.chars().take(s.length() - 1))` と書いたら、native だけ「`String.chars` needs the Unicode grapheme cluster tables, which target `native` does not support yet」でビルドが止まった．js と wasm は通る．

対応: コードポイント単位（`s.code_points()...`）に戻した．ビルド時に止まるので T1 より気づきやすい．

行き先: 我慢（native の対応待ち）．

## Brix

### B1. 文字列の生成器と「候補から選ぶ」生成器がない

やりたかったこと: 文字列の断片（`"""`、`#{`、`\`、改行など）をランダムに並べたソースで、トークンを連結すると元に戻ることを property で確かめる．

実際に書いたコード: 断片の配列の添字を `Gen.int_between` で生成し、`Gen.map` で文字列に組み立てた．

```emel
const PIECES = ["\"\"\"", "\"", "\#{", "}", ...]

gen = Gen.list(Gen.int_between(0, List.length(PIECES) - 1)) |> Gen.map(source_of)
```

縮小は添字を 0 へ寄せるので、反例は「最初の断片 `"""` の繰り返し」に向かって縮む．構造の上で意味のある縮み方ではない．

本来の形:

- `Gen.element(xs: List[A]) -> Gen[A]`: 候補から1つ選ぶ．縮小はリストの先頭へ寄せる
- `Gen.one_of(gens: List[Gen[A]]) -> Gen[A]`、`Gen.frequency(List[(Int, Gen[A])])`
- `Gen.string(gen: Gen[String]) -> Gen[String]`、または `Gen.list` の結果を `String.concat` する定番の組み合わせ
- `Gen.bind`（`flat_map`）: 生成した値で次の生成器を選ぶ

行き先: Brix．

### B2. Brix 0.4.0 が emela 0.28 で毎回警告を出す

起きたこと: `emela check` と `emela test` のたびに W0203（`brix is written for emela 0.27.0; this is 0.28.2`）が出る．中身は問題なく動く．

本来の形: Brix の `emela` を 0.28 に上げたリリース．

行き先: Brix（リリース作業）．

## 進め方

### P1. main の spec を読むと、リリースにない機能を使ってしまう

起きたこと: 本体リポジトリの `main` の spec を見て effect alias `x <- E` を書いたら、0.28.2 では `x < -E` という比較として読まれた．`emela fmt` もそのとおりに書き換えた．`x <- E` は 0.28.2 の後に main へ入った機能（emela-lang/emela#791）．

対応: spec はリリースタグで読む（README の Rules に追記済み）．本体には何も出さない．

lexer にも `<-` を1トークンにする処理が残っていた．corpus に `<-` がないのでトークン列の比較では見つからず、M2 で token の一覧を見直したときに気づいて消した．

### P2. 作業中に PATH の emela が main のビルドに切り替わった

起きたこと: `~/.emela/bin/emela` の参照先が、作業の途中で v0.28.2 から main のビルド（`main-a9d27cf`）に変わった．`emela check` が、0.28.2 にない W0403（`use Args` は非推奨、`args <- Args` と書け）を出し始めて気づいた．

対応: Graft の作業では `~/.emela/versions/v0.28.2` を PATH の先頭に置いた．CI は `setup-emela` が Pome.toml の版を入れるので影響しない．

行き先: 我慢．手元でも Pome.toml の `emela` と違う版で動いていることに気づける仕組み（W0203 に近い警告）があるとよいが、Graft の側で `scripts/` が版を確かめる方が早い．

### P3. メソッド呼び出しを知らずに、`List.f(List.g(xs, ...))` と書き続けていた

起きたこと: M2 まで、標準ライブラリの関数をすべて `List.length(List.filter(items, f))` や `Option.or(Map.get(m, k), [])` の形で書いていた．仕様 4.6 と 5.3 によれば、型を定義したモジュールの関数は `items.filter(f).length()` や `m.get(k).or([])` と書ける．std も `xys.reverse().fold(...)` と書いている．`cst.emel` の `same` を `impl Node: Eq` にできると指摘されて仕様を読み直し、気づいた．

対応: 受け手の型のモジュールの関数呼び出しを、約 300 か所メソッド呼び出しに書き換えた．あわせて、自前の `max` と行末の空白を削る関数を `Int.max` と `String.trim` に置き換え、同じ補助関数が2つずつあったもの（`spaces`、`newlines_from`）を1つにまとめた．書き換えの前後で、テスト、reference との比較 3 種、fuzz の結果は変わらない．

本体への材料: 仕様 6 章の冒頭は「呼び出しの形は `name(arguments)` の1つだけ」と書いている．メソッド呼び出しは 4.6 と 5.3 の箇条書きと `[type.rules]` にしか出てこない．6 章（関数と式）の冒頭に `x.f(...)` の形も書いてあれば、最初に読む章で気づけた．

行き先: 本体 issue（仕様の記述）を検討．
