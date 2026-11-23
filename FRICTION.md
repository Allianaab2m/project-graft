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

行き先: 我慢．ループを持たないのは言語の判断で、末尾呼び出しは保証されている．補助関数がモジュールの別の場所に散るのが読みにくさの主因なので、次はローカル fn（`[fn.local]`）で呼び出し元の中に置く書き方を試す．

### L7. 引数の関数型が、書いていない fails と uses について多相になる

やりたかったこと: `fn update(f: fn(Parser) -> Parser)` で受け取った関数を `State.update` に渡す．

起きたこと: `State.update` は純粋な関数を求めるので、E0321（`expected fails {}, found fails E(f)`）と E0403 になった．引数の型に節を書かないと、その関数はどんな error と effect も持ちうる扱いになる．

対応: `st.set(f(st.get()))` と書き換えた．

本来の形: 純粋な関数だけを受け取ると型に書く方法（`fn(Parser) -> Parser fails {} uses {}` のような形）が、仕様か診断の help で示されているとよい．

行き先: 我慢．診断に help を足す本体 issue にするかは、仕様を確かめてから決める．

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
