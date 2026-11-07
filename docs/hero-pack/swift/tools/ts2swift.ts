/**
 * ts2swift: a narrow TypeScript -> Swift transpiler for the GymLock hero pack.
 *
 * It understands exactly the dialect used by web-reference/hero13/mx/*.ts (and later the Ridge
 * painters): numeric code over tuples, arrays, records and small object types, with the board API.
 * Semantics follow PORTING-GUIDE.md: every number is a Double, `%` is JSMath.rem, Math.round is
 * JSMath.round, sorts are stable, JS truthiness is explicit, and every push happens in the same
 * order. Output relies on JSRuntime.swift (JS, JSMap, JSSet, JSTruthy).
 *
 * Usage: TSLIB=<path to typescript> bun ts2swift.ts matrix <outDir>
 */
const TSLIB = process.env.TSLIB ?? 'typescript';
const ts: any = (await import(TSLIB)).default ?? (await import(TSLIB));
import * as path from 'node:path';
import * as fs from 'node:fs';

const HERE = path.dirname(new URL(import.meta.url).pathname);
const PACK = path.resolve(HERE, '../..');
const WEB = path.join(PACK, 'web-reference');

// ------------------------------------------------------------------ program
export function makeProgram(files: string[]) {
  const options = {
    target: ts.ScriptTarget.ES2020,
    lib: ['lib.es2020.d.ts', 'lib.dom.d.ts'],
    jsx: ts.JsxEmit.Preserve,
    strict: true,
    noEmit: true,
    skipLibCheck: true,
    moduleResolution: ts.ModuleResolutionKind.Bundler,
    module: ts.ModuleKind.ESNext,
    allowImportingTsExtensions: true,
  };
  const program = ts.createProgram(files, options);
  return {program, checker: program.getTypeChecker()};
}

const SWIFT_KEYWORDS = new Set([
  'as', 'is', 'in', 'func', 'repeat', 'protocol', 'extension', 'struct', 'where', 'guard', 'defer', 'init', 'deinit',
  'subscript', 'inout', 'operator', 'Self', 'self', 'Any', 'internal', 'fileprivate', 'private', 'public', 'static',
  'associatedtype', 'rethrows', 'throws', 'default', 'case', 'switch', 'enum', 'class', 'let', 'var', 'import', 'typealias',
  'fallthrough', 'nil', 'true', 'false', 'super', 'Type', 'open', 'some', 'any', 'do', 'catch', 'try', 'throw', 'return',
]);
const esc = (n: string) => (SWIFT_KEYWORDS.has(n) ? '`' + n + '`' : n);

type Fn = {kind: 'draw' | 'func' | 'closure' | 'module' | 'iife' | 'method' | 'ctor'; ret: string; feLabel?: string; isDraw?: boolean};

export type Config = {
  /** symbol-name -> Swift type, for named types */
  typeMap: Record<string, string>;
  /** how to emit references to imported identifiers */
  importMap: Record<string, string>;
  /** structs/classes generated for anonymous object types: accumulated per file */
  enumName: string;
  /** returns a Swift expression for a property access on a known external type, or undefined */
  propHook?: (e: Emitter, node: any, objSwift: string) => string | undefined;
  /** returns a Swift expression for a call, or undefined */
  callHook?: (e: Emitter, node: any) => string | undefined;
  /** emits an object literal of a known external type, or undefined */
  objHook?: (e: Emitter, node: any, swType: string) => string | undefined;
  /** Int parameters (by position) of methods on a receiver of the given Swift type */
  intParams?: Record<string, Record<string, number[]>>;
  /** Bool parameters */
  labeledParams?: Record<string, Record<string, Record<number, string>>>;
  /** classes from the source that must be emitted (Ridge) */
  classMode?: boolean;
  /** Swift types whose values are value types (mutation needs `var`) */
  valueTypes?: Set<string>;
  /** top-level declarations to leave out (hand-written in Swift instead) */
  skip?: Set<string>;
  /** Ridge painters: Record/Partial aliases, builder objects, canvas styles */
  ridge?: boolean;
};

export class Emitter {
  lines: string[] = [];
  ind = 0;
  fnStack: Fn[] = [];
  tmp = 0;
  generated = new Map<string, string>(); // signature -> struct name
  genDecls: string[] = [];
  mutated = new Set<any>(); // symbols
  inoutParams = new Set<any>(); // param symbols that become inout
  shadowParams = new Set<any>();
  warnings: string[] = [];
  moduleSyms = new Set<any>();
  initBlockVars = new Map<any, string>();
  /** locals that are optional in Swift though TS types them non-null */
  optSyms = new Set<any>();
  constructor(public checker: any, public sf: any, public cfg: Config) {}

  // ---------------------------------------------------------------- output helpers
  w(s: string) {
    this.lines.push('    '.repeat(this.ind) + s);
  }
  warn(node: any, msg: string) {
    const {line} = this.sf.getLineAndCharacterOfPosition(node.getStart ? node.getStart() : 0);
    this.warnings.push(`${path.basename(this.sf.fileName)}:${line + 1}: ${msg}`);
  }
  fresh(p = '_t') {
    return `${p}${++this.tmp}`;
  }
  get fn(): Fn {
    return this.fnStack[this.fnStack.length - 1];
  }

  // ---------------------------------------------------------------- types
  typeOf(node: any) {
    return this.checker.getTypeAtLocation(node);
  }
  isNumber(t: any): boolean {
    if (!t) return false;
    if (t.flags & (ts.TypeFlags.NumberLike)) return true;
    if (t.isUnion && t.isUnion()) return t.types.every((x: any) => x.flags & ts.TypeFlags.NumberLike || x.flags & (ts.TypeFlags.Undefined | ts.TypeFlags.Null)) && t.types.some((x: any) => x.flags & ts.TypeFlags.NumberLike);
    return false;
  }
  isBool(t: any): boolean {
    if (!t) return false;
    if (t.flags & ts.TypeFlags.BooleanLike) return true;
    if (t.isUnion && t.isUnion()) return t.types.every((x: any) => x.flags & ts.TypeFlags.BooleanLike);
    return false;
  }
  isString(t: any): boolean {
    if (!t) return false;
    if (t.flags & ts.TypeFlags.StringLike) return true;
    if (t.isUnion && t.isUnion()) return t.types.every((x: any) => x.flags & ts.TypeFlags.StringLike);
    return false;
  }
  isOptional(t: any): boolean {
    return !!(t && t.isUnion && t.isUnion() && t.types.some((x: any) => x.flags & (ts.TypeFlags.Undefined | ts.TypeFlags.Null | ts.TypeFlags.Void)));
  }
  nonNull(t: any) {
    return this.checker.getNonNullableType(t);
  }
  isTuple(t: any) {
    return this.checker.isTupleType(t);
  }
  isArray(t: any) {
    return this.checker.isArrayType(t);
  }
  elemType(t: any) {
    const args = this.checker.getTypeArguments(t);
    return args[0];
  }
  symName(t: any): string | undefined {
    return t?.aliasSymbol?.name ?? t?.symbol?.name;
  }

  ty(t: any, ctx?: any): string {
    if (!t) return 'Double';
    const F = ts.TypeFlags;
    if (t.flags & (F.Any | F.Unknown)) return 'Double';
    if (t.flags & F.NumberLike) return 'Double';
    if (t.flags & F.BooleanLike) return 'Bool';
    if (t.flags & F.StringLike) return 'String';
    if (t.flags & (F.Void | F.Undefined)) return 'Void';
    if (t.flags & F.Null) return 'Void';
    if (t.isUnion && t.isUnion()) {
      const nn = t.types.filter((x: any) => !(x.flags & (F.Undefined | F.Null | F.Void)));
      const opt = nn.length < t.types.length;
      let base: string;
      if (nn.length === 0) return 'Void';
      if (nn.every((x: any) => x.flags & F.StringLike)) base = 'String';
      else if (nn.every((x: any) => x.flags & F.NumberLike)) base = 'Double';
      else if (nn.every((x: any) => x.flags & F.BooleanLike)) base = 'Bool';
      else if (nn.every((x: any) => x.flags & (F.StringLike | F.NumberLike))) base = 'String';
      else if (t.aliasSymbol && this.cfg.typeMap[t.aliasSymbol.name]) base = this.cfg.typeMap[t.aliasSymbol.name];
      else base = this.ty(nn[0], ctx);
      return opt ? this.optOf(base) : base;
    }
    const alias = t.aliasSymbol?.name;
    if (alias && this.cfg.typeMap[alias]) return this.cfg.typeMap[alias];
    if (this.cfg.ridge && alias === 'Record' && t.aliasTypeArguments?.length === 2) return `[String: ${this.ty(t.aliasTypeArguments[1], ctx)}]`;
    if (this.cfg.ridge && alias === 'Partial' && t.aliasTypeArguments?.length === 1) {
      const inner = t.aliasTypeArguments[0];
      const nm = inner.aliasSymbol?.name ?? inner.symbol?.name;
      const m = this.cfg.typeMap[`Partial<${nm}>`];
      if (m) return m;
    }
    if (this.isTuple(t)) {
      const args = this.checker.getTypeArguments(t);
      return '(' + args.map((a: any) => this.ty(a, ctx)).join(', ') + ')';
    }
    if (this.isArray(t)) return '[' + this.ty(this.elemType(t), ctx) + ']';
    const sym = t.symbol?.name;
    if (sym === 'Map') {
      const [k, v] = this.checker.getTypeArguments(t);
      return `JSMap<${this.ty(k)}, ${this.ty(v)}>`;
    }
    if (sym === 'Set') {
      const [k] = this.checker.getTypeArguments(t);
      return `JSSet<${this.ty(k)}>`;
    }
    if (sym && this.cfg.typeMap[sym]) return this.cfg.typeMap[sym];
    const sigs = t.getCallSignatures?.() ?? [];
    if (sigs.length > 0 && t.getProperties().length === 0) {
      const s = sigs[0];
      const ps = s.getParameters().map((p: any) => this.ty(this.checker.getTypeOfSymbolAtLocation(p, p.valueDeclaration)));
      const r = this.ty(this.checker.getReturnTypeOfSignature(s));
      return `(${ps.join(', ')}) -> ${r}`;
    }
    const strIdx = this.checker.getIndexInfoOfType(t, ts.IndexKind.String);
    if (strIdx) return `[String: ${this.ty(strIdx.type)}]`;
    const numIdx = this.checker.getIndexInfoOfType(t, ts.IndexKind.Number);
    if (numIdx) return `[Double: ${this.ty(numIdx.type)}]`;
    if (t.flags & F.Object) return this.objType(t);
    if (process.env.TSDBG) console.error("UNK", this.checker.typeToString(t));
    this.warnings.push(`unknown type ${this.checker.typeToString(t)} ${process.env.TSDBG ? new Error().stack!.split("\n").slice(2,6).join(" / ") : ""}`);
    return 'Double';
  }

  /** `T?`, parenthesising function types in ridge mode */
  optOf(base: string): string {
    if (this.cfg.ridge && /^\(.*\) -> /.test(base)) return `(${base})?`;
    return `${base}?`;
  }

  /** a class for an anonymous (or aliased) object type */
  probe = false;
  probeTy(t: any): string {
    const was = this.probe;
    this.probe = true;
    try {
      return this.ty(t);
    } finally {
      this.probe = was;
    }
  }
  objType(t: any): string {
    if (this.probe) return 'Obj';
    const props = t.getProperties();
    const names = props.map((p: any) => p.name);
    if (process.env.TSDBG && /Constructor/.test(this.checker.typeToString(t))) console.error(new Error().stack!.split("\n").slice(2,8).join(" / "));
    if (process.env.TSDBG) console.error("OBJ", this.checker.typeToString(t).slice(0,120), t.getProperties().map((p: any) => p.name + ":" + this.checker.typeToString(this.checker.getTypeOfSymbolAtLocation(p, p.valueDeclaration ?? this.sf))).join(","));
    const hook = this.cfg.typeMap['{' + names.slice().sort().join(',') + '}'];
    if (hook) return hook;
    const alias = t.aliasSymbol?.name ?? (t.symbol?.name && t.symbol.name !== '__type' && t.symbol.name !== '__object' ? t.symbol.name : undefined);
    const sig = (alias ?? '') + '{' + props.map((p: any) => `${p.name}:${this.checker.typeToString(this.checker.getTypeOfSymbolAtLocation(p, p.valueDeclaration ?? this.sf))}`).join(';') + '}';
    const have = this.generated.get(sig);
    if (have) return have;
    const name = alias ?? 'O_' + names.map((n: string) => n.replace(/[^A-Za-z0-9]/g, '')).join('_');
    let uniq = name, k = 2;
    while ([...this.generated.values()].includes(uniq)) uniq = name + k++;
    this.generated.set(sig, uniq);
    const fields = props.map((p: any) => {
      const pt = this.checker.getTypeOfSymbolAtLocation(p, p.valueDeclaration ?? this.sf);
      let sw = this.ty(pt);
      const optional = (p.flags & ts.SymbolFlags.Optional) !== 0;
      if (optional && !sw.endsWith('?')) sw = this.optOf(sw);
      return {n: esc(p.name), sw, optional};
    });
    const d: string[] = [];
    d.push(`nonisolated final class ${uniq} {`);
    for (const f of fields) d.push(`    var ${f.n}: ${f.sw}`);
    const esc2 = (sw: string) => (/^\(.*\) -> /.test(sw) && !sw.endsWith('?') ? `@escaping ${sw}` : sw);
    d.push(`    init(${fields.map((f: any) => `${f.n}: ${esc2(f.sw)}${f.optional ? ' = nil' : ''}`).join(', ')}) {`);
    for (const f of fields) d.push(`        self.${f.n} = ${f.n}`);
    d.push('    }');
    d.push('}');
    this.genDecls.push(d.join('\n'));
    return uniq;
  }

  /** the Swift default value of a type (for `new Array(n)`) */
  defaultOf(sw: string): string {
    if (sw === 'Double') return '0.0';
    if (sw === 'Bool') return 'false';
    if (sw === 'String') return '""';
    if (sw.endsWith('?')) return 'nil';
    if (sw.startsWith('[')) return '[]';
    if (sw.startsWith('(')) {
      const inner = splitTop(sw.slice(1, -1));
      return '(' + inner.map((x) => this.defaultOf(x.trim())).join(', ') + ')';
    }
    return 'nil';
  }

  // ---------------------------------------------------------------- mutation analysis
  analyzeMutations(root: any) {
    const visit = (n: any) => {
      const markRoot = (e: any, deep: boolean) => {
        let x = e;
        while (ts.isParenthesizedExpression(x) || ts.isNonNullExpression(x) || ts.isAsExpression(x)) x = x.expression;
        if (ts.isConditionalExpression(x)) {
          markRoot(x.whenTrue, deep);
          markRoot(x.whenFalse, deep);
          return;
        }
        if (ts.isIdentifier(x)) {
          const s = this.checker.getSymbolAtLocation(x);
          if (s) this.mutated.add(s);
          return;
        }
        if (deep && (ts.isElementAccessExpression(x) || ts.isPropertyAccessExpression(x))) {
          // a[i] = v / a.length = v / t[0] = v mutate a when it is a value type
          const ot = this.typeOf(x.expression);
          const sw = this.probeTy(ot);
          if (sw.startsWith('[') || sw.startsWith('(') || sw.startsWith('JSMap') || sw.startsWith('JSSet') || this.cfg.valueTypes?.has(sw)) markRoot(x.expression, true);
        }
      };
      if (ts.isBinaryExpression(n) && n.operatorToken.kind >= ts.SyntaxKind.FirstAssignment && n.operatorToken.kind <= ts.SyntaxKind.LastAssignment) markRoot(n.left, true);
      if ((ts.isPrefixUnaryExpression(n) || ts.isPostfixUnaryExpression(n)) && (n.operator === ts.SyntaxKind.PlusPlusToken || n.operator === ts.SyntaxKind.MinusMinusToken)) markRoot(n.operand, true);
      if (ts.isCallExpression(n) && ts.isPropertyAccessExpression(n.expression)) {
        const m = n.expression.name.text;
        const rt = this.typeOf(n.expression.expression);
        const sw = this.probeTy(rt);
        const valueish = sw.startsWith('[') || sw.startsWith('JSMap') || sw.startsWith('JSSet');
        if (valueish && ['push', 'sort', 'splice', 'pop', 'shift', 'unshift', 'reverse', 'fill', 'set', 'add', 'delete', 'clear'].includes(m)) markRoot(n.expression.expression, true);
      }
      ts.forEachChild(n, visit);
    };
    visit(root);
    // array/map/set params mutated inside their function become inout
    const fnVisit = (n: any) => {
      if (ts.isFunctionDeclaration(n) || ts.isArrowFunction(n) || ts.isFunctionExpression(n) || ts.isMethodDeclaration(n)) {
        for (const p of n.parameters) {
          if (!ts.isIdentifier(p.name)) continue;
          const s = this.checker.getSymbolAtLocation(p.name);
          if (!s || !this.mutated.has(s)) continue;
          const sw = this.probeTy(this.typeOf(p.name));
          if (sw.startsWith('[') || sw.startsWith('JSMap') || sw.startsWith('JSSet') || sw.startsWith('(')) this.inoutParams.add(s);
          else this.shadowParams.add(s);
        }
      }
      ts.forEachChild(n, fnVisit);
    };
    fnVisit(root);
  }
  isMutated(nameNode: any) {
    const s = this.checker.getSymbolAtLocation(nameNode);
    return s ? this.mutated.has(s) : true;
  }

  // ---------------------------------------------------------------- expression helpers
  num(text: string): string {
    let s = text.replace(/_/g, '');
    if (/^0[xX]/.test(s)) return String(Number(s)) + '.0';
    if (s.startsWith('.')) s = '0' + s;
    if (s.endsWith('.')) s = s + '0';
    if (/[.eE]/.test(s)) {
      // 1e4 is fine in Swift; 5e-1 is fine
      return s;
    }
    return s + '.0';
  }

  unwrapParens(e: any): any {
    while (ts.isParenthesizedExpression(e) || ts.isAsExpression(e) || ts.isNonNullExpression(e) || ts.isTypeAssertionExpression?.(e) || ts.isSatisfiesExpression?.(e)) e = e.expression;
    return e;
  }

  /** an Int expression (array index, board color flag) */
  int(e: any): string {
    const u = this.unwrapParens(e);
    if (ts.isNumericLiteral(u)) {
      const v = Number(u.text);
      if (Number.isInteger(v)) return String(v);
    }
    if (ts.isPrefixUnaryExpression(u) && u.operator === ts.SyntaxKind.MinusToken && ts.isNumericLiteral(u.operand)) return '-' + u.operand.text;
    if (ts.isPropertyAccessExpression(u) && u.name.text === 'length') return this.countOf(u.expression);
    if (ts.isConditionalExpression(u)) return `(${this.cond(u.condition)} ? ${this.int(u.whenTrue)} : ${this.int(u.whenFalse)})`;
    return `Int(${this.expr(e)})`;
  }
  /** a JS truthy flag passed where Swift wants Int 0/1 */
  flag(e: any): string {
    const u = this.unwrapParens(e);
    if (ts.isNumericLiteral(u)) return Number(u.text) ? '1' : '0';
    if (ts.isConditionalExpression(u)) return `(${this.cond(u.condition)} ? ${this.flag(u.whenTrue)} : ${this.flag(u.whenFalse)})`;
    const t = this.typeOf(u);
    if (this.isBool(t)) return `(${this.expr(u)} ? 1 : 0)`;
    return `JS.flag(${this.expr(u)})`;
  }
  countOf(e: any): string {
    const t = this.typeOf(e);
    if (this.isString(t)) return `${this.expr(e)}.utf16.count`;
    return `${this.expr(e)}.count`;
  }

  /** a Swift Bool for a JS condition */
  cond(e: any): string {
    const u = this.unwrapParens(e);
    if (ts.isPrefixUnaryExpression(u) && u.operator === ts.SyntaxKind.ExclamationToken) {
      const inner = this.unwrapParens(u.operand);
      const it = this.typeOf(inner);
      if (this.isOptionalRef(inner) && this.isBool(this.nonNull(it))) return `!(${this.expr(inner, {noForce: true})} ?? false)`;
      if (this.isOptionalRef(inner)) return `${this.expr(inner, {noForce: true})} == nil`;
      if (this.isNumber(it)) return `${this.wrap(this.expr(inner))} == 0`;
      return `!${this.wrap(this.cond(inner))}`;
    }
    if (ts.isBinaryExpression(u)) {
      const k = u.operatorToken.kind;
      if (k === ts.SyntaxKind.AmpersandAmpersandToken) return `(${this.cond(u.left)} && ${this.cond(u.right)})`;
      if (k === ts.SyntaxKind.BarBarToken) return `(${this.cond(u.left)} || ${this.cond(u.right)})`;
    }
    const t = this.typeOf(u);
    if (this.isBool(t)) return this.expr(u);
    if (this.isOptionalRef(u) && this.isBool(this.nonNull(t))) return `(${this.expr(u, {noForce: true})} ?? false)`;
    if (this.isOptionalRef(u)) return `${this.expr(u, {noForce: true})} != nil`;
    if (this.isNumber(t)) return `${this.wrap(this.expr(u))} != 0`;
    if (this.isString(t)) return `!${this.wrap(this.expr(u))}.isEmpty`;
    if (this.isOptional(t)) return `${this.wrap(this.expr(u, {noForce: true}))} != nil`;
    return 'true';
  }
  isOptionalRef(e: any): boolean {
    const u = this.unwrapParens(e);
    if (!ts.isIdentifier(u) && !ts.isPropertyAccessExpression(u) && !ts.isElementAccessExpression(u) && !ts.isCallExpression(u)) return false;
    if (ts.isIdentifier(u)) {
      const s = this.checker.getSymbolAtLocation(u);
      if (s && this.optSyms.has(s)) return true;
      const d = s?.valueDeclaration;
      if (d) {
        const dt = this.checker.getTypeOfSymbolAtLocation(s, d);
        return this.isOptional(dt);
      }
    }
    if (ts.isElementAccessExpression(u)) {
      const ot = this.typeOf(u.expression);
      if (this.ty(ot).startsWith('[String:') || this.ty(ot).startsWith('[Double:')) return true;
    }
    if (ts.isCallExpression(u) && ts.isPropertyAccessExpression(u.expression) && u.expression.name.text === 'get') return true;
    return this.isOptional(this.typeOf(u));
  }
  wrap(s: string) {
    return /^[A-Za-z_][A-Za-z0-9_.]*$/.test(s) || /^\(.*\)$/.test(s) && balanced(s.slice(1, -1)) ? s : `(${s})`;
  }

  /** an expression coerced to a Swift type */
  as(e: any, want: string): string {
    const u = this.unwrapParens(e);
    if (want === 'Bool') return this.cond(e);
    if (want === 'Int') return this.int(e);
    if (want === 'String') {
      if (ts.isConditionalExpression(u)) return `(${this.cond(u.condition)} ? ${this.as(u.whenTrue, 'String')} : ${this.as(u.whenFalse, 'String')})`;
      const t = this.typeOf(u);
      if (this.isNumber(t) && !this.isString(t)) return `JS.str(${this.expr(u)})`;
      return this.expr(u);
    }
    if (want === 'Double') {
      const t = this.typeOf(u);
      if (this.isBool(t)) return `(${this.expr(u)} ? 1.0 : 0.0)`;
    }
    // A function reference with fewer params than the wanted closure type: JS ignores the extras.
    const fm = /^\((.*)\) -> .+$/.exec(/^\(\(.*\) -> .*\)$/.test(want) ? want.slice(1, -1) : want);
    if (fm && ts.isIdentifier(u)) {
      const sigs = this.typeOf(u).getCallSignatures?.() ?? [];
      if (sigs.length === 1) {
        let depth = 0, n = fm[1].trim() ? 1 : 0;
        for (const ch of fm[1]) { if (ch === '(' || ch === '[' || ch === '<') depth++; else if (ch === ')' || ch === ']' || ch === '>') depth--; else if (ch === ',' && depth === 0) n++; }
        const have = sigs[0].getParameters().length;
        if (have < n) {
          const names = Array.from({length: n}, (_, i) => `_a${i}`);
          return `{ ${names.join(', ')} in ${this.expr(u)}(${names.slice(0, have).join(', ')}) }`;
        }
      }
    }
    return this.expr(e, {want});
  }

  // ---------------------------------------------------------------- expressions
  expr(e: any, o: {noForce?: boolean; want?: string; stmt?: boolean} = {}): string {
    const K = ts.SyntaxKind;
    switch (e.kind) {
      case K.NumericLiteral:
        return this.num(e.text);
      case K.StringLiteral:
      case K.NoSubstitutionTemplateLiteral:
        return JSON.stringify(e.text);
      case K.TrueKeyword:
        return 'true';
      case K.FalseKeyword:
        return 'false';
      case K.NullKeyword:
        return 'nil';
      case K.ThisKeyword:
        return 'self';
      case K.TemplateExpression: {
        let s = '"' + strEsc(e.head.text);
        for (const sp of e.templateSpans) {
          s += `\\(${this.as(sp.expression, 'String')})` + strEsc(sp.literal.text);
        }
        return s + '"';
      }
      case K.Identifier:
        return this.ident(e, o);
      case K.ParenthesizedExpression:
        return `(${this.expr(e.expression, o)})`;
      case K.AsExpression:
      case K.SatisfiesExpression:
      case K.TypeAssertionExpression:
        return this.expr(e.expression, o);
      case K.NonNullExpression: {
        const inner = this.expr(e.expression, {noForce: true});
        const u = this.unwrapParens(e.expression);
        if (this.isOptionalRef(u)) return `${this.wrap(inner)}!`;
        return inner;
      }
      case K.PrefixUnaryExpression:
        return this.prefix(e, o);
      case K.PostfixUnaryExpression: {
        const fnn = e.operator === K.PlusPlusToken ? 'postInc' : 'postDec';
        return `JS.${fnn}(&${this.lvalue(e.operand)})`;
      }
      case K.BinaryExpression:
        return this.binary(e, o);
      case K.ConditionalExpression: {
        const want = o.want;
        const a = want ? this.as(e.whenTrue, want) : this.expr(e.whenTrue);
        const b = want ? this.as(e.whenFalse, want) : this.expr(e.whenFalse);
        return `(${this.cond(e.condition)} ? ${a} : ${b})`;
      }
      case K.CallExpression:
        return this.call(e, o);
      case K.PropertyAccessExpression:
        return this.prop(e, o);
      case K.ElementAccessExpression:
        return this.elem(e, o);
      case K.ArrayLiteralExpression:
        return this.arrayLit(e);
      case K.ObjectLiteralExpression:
        return this.objLit(e);
      case K.ArrowFunction:
      case K.FunctionExpression:
        return this.closure(e);
      case K.NewExpression:
        return this.newExpr(e);
      case K.VoidExpression:
        return 'nil';
      case K.TypeOfExpression:
        this.warn(e, 'typeof');
        return '""';
      case K.SpreadElement:
        return this.expr(e.expression);
      default:
        this.warn(e, `unsupported expression ${K[e.kind]}`);
        return `/*?${K[e.kind]}*/0`;
    }
  }

  ident(e: any, o: {noForce?: boolean} = {}): string {
    const n = e.text;
    if (n === 'undefined') return 'nil';
    if (n === 'Infinity') return 'Double.infinity';
    if (n === 'NaN') return 'Double.nan';
    const s = this.checker.getSymbolAtLocation(e);
    let sym = s;
    if (sym && sym.flags & ts.SymbolFlags.Alias) sym = this.checker.getAliasedSymbol(sym);
    const decl = sym?.valueDeclaration ?? sym?.declarations?.[0];
    if (decl && decl.getSourceFile() !== this.sf) {
      const mapped = this.cfg.importMap[n] ?? this.cfg.importMap[sym.name];
      if (mapped !== undefined) return mapped;
    }
    const ib = s && this.initBlockVars.get(s);
    let out = esc(n);
    if (!o.noForce && s && decl && decl.getSourceFile() === this.sf) {
      // TS narrowing: declared optional, narrowed to non-null here
      const declT = this.checker.getTypeOfSymbolAtLocation(s, decl);
      const here = this.typeOf(e);
      if (this.isOptional(declT) && !this.isOptional(here) && !(here.flags & ts.TypeFlags.Never)) out += '!';
    }
    void ib;
    if (!o.noForce && s && this.optSyms.has(s)) out += '!';
    return out;
  }

  lvalue(e: any): string {
    const u = this.unwrapParens(e);
    if (ts.isIdentifier(u)) return this.ident(u, {noForce: true});
    if (ts.isPropertyAccessExpression(u)) return this.prop(u, {noForce: true});
    if (ts.isElementAccessExpression(u)) return this.elem(u, {noForce: true});
    return this.expr(u);
  }

  prefix(e: any, o: any): string {
    const K = ts.SyntaxKind;
    switch (e.operator) {
      case K.ExclamationToken:
        return `(${this.cond(e)})`;
      case K.MinusToken: {
        const inner = this.expr(e.operand);
        return `-${this.wrap(inner)}`;
      }
      case K.PlusToken:
        return this.as(e.operand, 'Double');
      case K.TildeToken:
        return `JS.bitNot(${this.expr(e.operand)})`;
      case K.PlusPlusToken:
        return `JS.preInc(&${this.lvalue(e.operand)})`;
      case K.MinusMinusToken:
        return `JS.preDec(&${this.lvalue(e.operand)})`;
    }
    void o;
    return this.expr(e.operand);
  }

  binary(e: any, o: any): string {
    const K = ts.SyntaxKind;
    const k = e.operatorToken.kind;
    const L = e.left, R = e.right;
    const lt = this.typeOf(L), rt = this.typeOf(R);
    if (k === K.EqualsToken) {
      return `${this.assignTarget(L)} = ${this.assignValue(L, R)}`;
    }
    if (k >= K.FirstCompoundAssignment && k <= K.LastCompoundAssignment) {
      const lv = this.assignTarget(L);
      const rv = this.expr(R);
      switch (k) {
        case K.PlusEqualsToken:
          if (this.isString(lt) && !this.isString(rt)) return `${lv} += ${this.as(R, 'String')}`;
          return `${lv} += ${rv}`;
        case K.MinusEqualsToken:
          return `${lv} -= ${rv}`;
        case K.AsteriskEqualsToken:
          return `${lv} *= ${rv}`;
        case K.SlashEqualsToken:
          return `${lv} /= ${rv}`;
        case K.PercentEqualsToken:
          return `${lv} = JSMath.rem(${lv}, ${rv})`;
        case K.BarBarEqualsToken:
          return `${lv} = JS.or(${lv}, ${rv})`;
        case K.QuestionQuestionEqualsToken:
          return `${lv} = ${lv} ?? ${rv}`;
        default:
          this.warn(e, 'compound op');
          return `${lv} = ${rv}`;
      }
    }
    switch (k) {
      case K.PlusToken:
        if (this.isString(lt) || this.isString(rt)) return `${this.wrapS(this.as(L, 'String'))} + ${this.wrapS(this.as(R, 'String'))}`;
        return `${this.expr(L)} + ${this.expr(R)}`;
      case K.MinusToken:
        return `${this.expr(L)} - ${this.wrapNeg(R)}`;
      case K.AsteriskToken:
        return `${this.wrapMul(L)} * ${this.wrapMul(R)}`;
      case K.SlashToken:
        return `${this.wrapMul(L)} / ${this.wrapDiv(R)}`;
      case K.PercentToken:
        return `JSMath.rem(${this.expr(L)}, ${this.expr(R)})`;
      case K.AsteriskAsteriskToken: {
        const ru = this.unwrapParens(R);
        if (ts.isNumericLiteral(ru) && ru.text === '2') return `JS.sq(${this.expr(L)})`;
        return `JS.pow(${this.expr(L)}, ${this.expr(R)})`;
      }
      case K.EqualsEqualsEqualsToken:
      case K.EqualsEqualsToken:
        return this.equality(L, R, '==');
      case K.ExclamationEqualsEqualsToken:
      case K.ExclamationEqualsToken:
        return this.equality(L, R, '!=');
      case K.LessThanToken:
        return `${this.expr(L)} < ${this.expr(R)}`;
      case K.LessThanEqualsToken:
        return `${this.expr(L)} <= ${this.expr(R)}`;
      case K.GreaterThanToken:
        return `${this.expr(L)} > ${this.expr(R)}`;
      case K.GreaterThanEqualsToken:
        return `${this.expr(L)} >= ${this.expr(R)}`;
      case K.AmpersandAmpersandToken:
        if (this.isBool(lt) && this.isBool(rt)) return `${this.expr(L)} && ${this.expr(R)}`;
        if (o.want === 'Bool') return `${this.cond(L)} && ${this.cond(R)}`;
        if (this.isBool(rt) || this.isBool(lt)) return `(${this.cond(L)} && ${this.cond(R)})`;
        return `JS.and(${this.expr(L)}, ${this.expr(R)})`;
      case K.BarBarToken:
        if (this.isBool(lt) && this.isBool(rt)) return `${this.expr(L)} || ${this.expr(R)}`;
        if (o.want === 'Bool') return `${this.cond(L)} || ${this.cond(R)}`;
        return `JS.or(${this.expr(L)}, ${this.expr(R)})`;
      case K.QuestionQuestionToken: {
        const ru = this.unwrapParens(R);
        if (ru.kind === K.NullKeyword || (ts.isIdentifier(ru) && ru.text === 'undefined')) return this.expr(L, {noForce: true});
        return `(${this.expr(L, {noForce: true})} ?? ${this.expr(R)})`;
      }
      case K.BarToken:
        return `JS.bitOr(${this.expr(L)}, ${this.expr(R)})`;
      case K.AmpersandToken:
        return `JS.bitAnd(${this.expr(L)}, ${this.expr(R)})`;
      case K.CaretToken:
        return `JS.bitXor(${this.expr(L)}, ${this.expr(R)})`;
      case K.LessThanLessThanToken:
        return `JS.shl(${this.expr(L)}, ${this.expr(R)})`;
      case K.GreaterThanGreaterThanToken:
        return `JS.shr(${this.expr(L)}, ${this.expr(R)})`;
      case K.GreaterThanGreaterThanGreaterThanToken:
        return `JS.ushr(${this.expr(L)}, ${this.expr(R)})`;
      case K.CommaToken:
        this.warn(e, 'comma in expression');
        return `JS.comma(${this.expr(L)}, ${this.expr(R)})`;
      case K.InKeyword:
        return `(${this.expr(R)}[${this.expr(L)}] != nil)`;
      case K.InstanceOfKeyword:
        return `(${this.expr(L)} is ${this.expr(R)})`;
    }
    this.warn(e, `binary ${K[k]}`);
    return `${this.expr(L)} /*${K[k]}*/ ${this.expr(R)}`;
  }
  equality(L: any, R: any, op: string): string {
    const lu = this.unwrapParens(L), ru = this.unwrapParens(R);
    const isNil = (x: any) => x.kind === ts.SyntaxKind.NullKeyword || (ts.isIdentifier(x) && x.text === 'undefined');
    if (isNil(ru)) return `${this.expr(L, {noForce: true})} ${op} nil`;
    if (isNil(lu)) return `${this.expr(R, {noForce: true})} ${op} nil`;
    const lt = this.typeOf(L), rt = this.typeOf(R);
    if (this.isBool(lt) && this.isNumber(rt)) return `${this.as(L, 'Double')} ${op} ${this.expr(R)}`;
    if (this.isNumber(lt) && this.isBool(rt)) return `${this.expr(L)} ${op} ${this.as(R, 'Double')}`;
    return `${this.expr(L)} ${op} ${this.expr(R)}`;
  }
  wrapS(s: string) {
    return s;
  }
  /** right operand of `-`: parenthesise sums */
  wrapNeg(R: any) {
    const s = this.expr(R);
    const u = R;
    if (ts.isBinaryExpression(u) && (u.operatorToken.kind === ts.SyntaxKind.PlusToken || u.operatorToken.kind === ts.SyntaxKind.MinusToken)) return `(${s})`;
    if (ts.isConditionalExpression(u)) return `(${s})`;
    return s;
  }
  wrapMul(X: any) {
    const s = this.expr(X);
    if (ts.isBinaryExpression(X) && [ts.SyntaxKind.PlusToken, ts.SyntaxKind.MinusToken].includes(X.operatorToken.kind)) return `(${s})`;
    if (ts.isConditionalExpression(X)) return `(${s})`;
    return s;
  }
  wrapDiv(X: any) {
    const s = this.expr(X);
    if (ts.isBinaryExpression(X) && [ts.SyntaxKind.PlusToken, ts.SyntaxKind.MinusToken, ts.SyntaxKind.AsteriskToken, ts.SyntaxKind.SlashToken].includes(X.operatorToken.kind)) return `(${s})`;
    if (ts.isConditionalExpression(X)) return `(${s})`;
    return s;
  }

  assignTarget(L: any): string {
    const u = this.unwrapParens(L);
    if (ts.isPropertyAccessExpression(u) && u.name.text === 'length') return `/*length*/${this.lvalue(u.expression)}`;
    return this.lvalue(u);
  }
  assignValue(L: any, R: any): string {
    if (this.cfg.ridge) {
      const lu = this.unwrapParens(L);
      if (ts.isPropertyAccessExpression(lu) && (lu.name.text === 'fillStyle' || lu.name.text === 'strokeStyle')) {
        const ru = this.unwrapParens(R);
        if (ts.isStringLiteral(ru) || ts.isNoSubstitutionTemplateLiteral(ru)) return JSON.stringify(ru.text);
        return `C2DStyle(${this.expr(ru)})`;
      }
    }
    const lt = this.typeOf(L);
    const sw = this.ty(lt);
    if (sw === 'Double') return this.as(R, 'Double');
    if (sw === 'String') return this.as(R, 'String');
    if (sw === 'Bool') return this.cond(R);
    return this.expr(R, {want: sw});
  }

  // ---------------------------------------------------------------- property / element access
  prop(e: any, o: {noForce?: boolean} = {}): string {
    const obj = e.expression;
    const name = e.name.text;
    // Math.PI etc.
    if (ts.isIdentifier(obj) && obj.text === 'Math') {
      if (name === 'PI') return 'Double.pi';
      if (name === 'E') return 'M_E';
      if (name === 'SQRT2') return '2.0.squareRoot()';
      if (name === 'LN2') return 'M_LN2';
      return `JS.${name}`;
    }
    if (ts.isIdentifier(obj) && obj.text === 'Number') {
      if (name === 'EPSILON') return 'Double.ulpOfOne';
      if (name === 'MAX_VALUE') return 'Double.greatestFiniteMagnitude';
      if (name === 'POSITIVE_INFINITY') return 'Double.infinity';
      if (name === 'NEGATIVE_INFINITY') return '-Double.infinity';
    }
    const ot = this.typeOf(obj);
    if (name === 'length' && (this.isArray(ot) || this.isString(ot) || this.isTuple(ot))) return `Double(${this.countOf(obj)})`;
    if (name === 'size' && /^JS(Map|Set)/.test(this.ty(ot))) return `Double(${this.expr(obj)}.count)`;
    const os = this.expr(obj);
    if (this.cfg.propHook) {
      const h = this.cfg.propHook(this, e, os);
      if (h !== undefined) return h;
    }
    const sw = this.ty(this.nonNull(ot));
    if (sw.startsWith('[String:')) {
      const v = `${this.wrap(os)}[${JSON.stringify(name)}]`;
      return o.noForce ? v : `${v}!`;
    }
    let base = this.wrap(os);
    if (e.questionDotToken) base += '?';
    let out = `${base}.${esc(name)}`;
    // TS narrowing on a property: declared optional, narrowed to non-null here
    if (!o.noForce && !e.questionDotToken) {
      const ps = this.checker.getSymbolAtLocation(e.name);
      const pd = ps?.valueDeclaration;
      if (ps && pd && (ts.isPropertySignature(pd) || ts.isPropertyDeclaration(pd))) {
        const declT = this.checker.getTypeOfSymbolAtLocation(ps, pd);
        const here = this.typeOf(e);
        if (this.isOptional(declT) && !this.isOptional(here) && !(here.flags & ts.TypeFlags.Never)) out += '!';
      }
      // ridge builders: the Swift field is optional though TS sees a (narrowed) value
      const bf = this.cfg.ridge ? RIDGE_FIELDS[sw]?.[name] : undefined;
      if (bf && bf.endsWith('?') && !out.endsWith('!')) {
        const here = this.typeOf(e);
        if (!this.isOptional(here) && !(here.flags & ts.TypeFlags.Never)) out += '!';
      }
    }
    return out;
  }

  elem(e: any, o: {noForce?: boolean} = {}): string {
    const obj = e.expression;
    const idx = e.argumentExpression;
    const ot = this.nonNull(this.typeOf(obj));
    const os = this.wrap(this.expr(obj));
    if (this.isTuple(ot)) {
      const u = this.unwrapParens(idx);
      if (ts.isNumericLiteral(u)) return `${os}.${u.text}`;
      return `JS.tupleAt(${os}, ${this.int(idx)})`;
    }
    if (this.isString(ot)) return `JS.at(${os}, ${this.expr(idx)})`;
    const sw = this.ty(ot);
    if (sw.startsWith('[String:')) {
      const v = `${os}[${this.as(idx, 'String')}]`;
      return o.noForce ? v : `${v}!`;
    }
    if (sw.startsWith('[Double:')) {
      const v = `${os}[${this.expr(idx)}]`;
      return o.noForce ? v : `${v}!`;
    }
    if (sw.startsWith('[')) return `${os}[${this.int(idx)}]`;
    if (this.cfg.propHook) {
      const h = this.cfg.propHook(this, e, os);
      if (h !== undefined) return h;
    }
    this.warn(e, `element access on ${sw}`);
    return `${os}[${this.expr(idx)}]`;
  }

  // ---------------------------------------------------------------- literals
  arrayLit(e: any, forceType?: string): string {
    const t = this.typeOf(e);
    const ctxT = this.checker.getContextualType(e);
    const useT = forceType ? undefined : (ctxT && this.isTuple(ctxT) ? ctxT : t);
    if (!forceType && this.cfg.ridge && this.isTuple(useT) && e.elements.some((x: any) => ts.isSpreadElement(x)) && e.elements.every((x: any) => !ts.isSpreadElement(x) || this.isTuple(this.nonNull(this.typeOf(x.expression))))) {
      // [...tuple, v] into a tuple: bind each spread once, then list its fields
      const args = this.checker.getTypeArguments(useT);
      const pre: string[] = [];
      const parts: string[] = [];
      for (const x of e.elements) {
        if (ts.isSpreadElement(x)) {
          const st = this.nonNull(this.typeOf(x.expression));
          const n = this.checker.getTypeArguments(st).length;
          const tv = this.fresh('_s');
          pre.push(`let ${tv} = ${this.expr(x.expression)}`);
          for (let j = 0; j < n; j++) parts.push(`${tv}.${j}`);
        } else parts.push(this.as(x, this.ty(args[parts.length])));
      }
      return `{ () -> ${this.ty(useT)} in ${pre.join('; ')}; return (${parts.join(', ')}) }()`;
    }
    if (!forceType && this.isTuple(useT) && !e.elements.some((x: any) => ts.isSpreadElement(x))) {
      const args = this.checker.getTypeArguments(useT);
      const parts = e.elements.map((x: any, i: number) => this.as(x, this.ty(args[i])));
      if (parts.length === 1) return parts[0];
      return `(${parts.join(', ')})`;
    }
    const sw = forceType ?? this.ty(this.isArray(t) ? t : ctxT && this.isArray(ctxT) ? ctxT : t);
    const elT = sw.startsWith('[') ? sw.slice(1, -1) : 'Double';
    const groups: string[] = [];
    let cur: string[] = [];
    const flush = () => {
      if (cur.length) groups.push(`[${cur.join(', ')}]`);
      cur = [];
    };
    for (const x of e.elements) {
      if (ts.isSpreadElement(x)) {
        flush();
        const st = this.typeOf(x.expression);
        if (this.isString(st)) groups.push(`JS.chars(${this.expr(x.expression)})`);
        else {
          const se = this.unwrapParens(x.expression);
          if (ts.isArrayLiteralExpression(se)) groups.push(this.arrayLit(se, sw));
          else if (ts.isConditionalExpression(se)) groups.push(`(${this.cond(se.condition)} ? ${this.arrOf(se.whenTrue, sw)} : ${this.arrOf(se.whenFalse, sw)})`);
          else groups.push(`Array(${this.expr(x.expression)})`);
        }
      } else if (ts.isOmittedExpression(x)) cur.push(this.defaultOf(elT));
      else cur.push(this.elemValue(x, elT));
    }
    flush();
    if (groups.length === 0) return `([] as ${sw})`;
    if (groups.length === 1) {
      const g = groups[0];
      if (g.startsWith('[')) return `(${g} as ${sw})`;
      return g;
    }
    return '(' + groups.map((g) => (g.startsWith('[') ? `(${g} as ${sw})` : g)).join(' + ') + ')';
  }
  arrOf(x: any, sw: string) {
    const u = this.unwrapParens(x);
    if (ts.isArrayLiteralExpression(u)) return this.arrayLit(u, sw);
    return this.expr(x);
  }
  elemValue(x: any, elT: string): string {
    if (elT === 'Double') return this.as(x, 'Double');
    if (elT === 'String') return this.as(x, 'String');
    if (elT === 'Bool') return this.cond(x);
    const u = this.unwrapParens(x);
    if (ts.isArrayLiteralExpression(u) && elT.startsWith('(')) {
      const parts = splitTop(elT.slice(1, -1));
      return '(' + u.elements.map((y: any, i: number) => this.elemValue(y, (parts[i] ?? 'Double').trim())).join(', ') + ')';
    }
    if (ts.isArrayLiteralExpression(u) && elT.startsWith('[')) return this.arrayLit(u, elT);
    if (ts.isObjectLiteralExpression(u)) return this.objLit(u, elT);
    return this.expr(x, {want: elT});
  }

  objLit(e: any, forceSw?: string): string {
    const ctxT = this.checker.getContextualType(e);
    const t = this.typeOf(e);
    let sw = forceSw ?? (ctxT ? this.ty(this.nonNull(ctxT)) : this.ty(t));
    if (sw === 'Double') sw = this.ty(t);
    if (this.cfg.objHook) {
      const h = this.cfg.objHook(this, e, sw);
      if (h !== undefined) return h;
    }
    const props: [string, any][] = [];
    for (const p of e.properties) {
      if (ts.isPropertyAssignment(p)) props.push([propName(p.name), p.initializer]);
      else if (ts.isShorthandPropertyAssignment(p)) props.push([p.name.text, p.name]);
      else if (ts.isMethodDeclaration(p)) props.push([propName(p.name), p]);
      else if (ts.isSpreadAssignment(p)) {
        const base = this.expr(p.expression);
        for (const sp of this.typeOf(p.expression).getProperties()) props.push([sp.name, {raw: `${base}.${esc(sp.name)}`}]);
      } else this.warn(p, 'object literal member');
    }
    if (sw.startsWith('[String:')) {
      const vT = sw.slice(sw.indexOf(':') + 1, -1).trim();
      if (props.length === 0) return `([:] as ${sw})`;
      return `([${props.map(([k, v]) => `${JSON.stringify(k)}: ${this.elemValue(v, vT)}`).join(', ')}] as ${sw})`;
    }
    // a generated class: arguments in declaration order
    const target = ctxT ? this.nonNull(ctxT) : t;
    const tprops = (target.getProperties ? target.getProperties() : []) as any[];
    const args: string[] = [];
    for (const tp of tprops) {
      const found = [...props].reverse().find(([k]) => k === tp.name);
      if (!found) continue;
      const pt = this.checker.getTypeOfSymbolAtLocation(tp, tp.valueDeclaration ?? e);
      let psw = this.ty(pt);
      if (psw.endsWith('?')) psw = psw.slice(0, -1);
      args.push(`${esc(tp.name)}: ${found[1].raw !== undefined ? found[1].raw : this.elemValue(found[1], psw)}`);
    }
    return `${sw.replace(/\?$/, '')}(${args.join(', ')})`;
  }

  newExpr(e: any): string {
    const c = e.expression.getText();
    const args = e.arguments ?? [];
    const t = this.typeOf(e);
    const sw = this.ty(t);
    if (c === 'Map' || c === 'Set') return `${sw}()`;
    if (c === 'Array') {
      const ctxT = this.checker.getContextualType(e);
      const csw = ctxT ? this.ty(this.nonNull(ctxT)) : sw;
      const el = (csw.startsWith('[') ? csw : sw).slice(1, -1);
      return `JS.newArray(${this.expr(args[0])}, ${this.defaultOf(el)})`;
    }
    if (c === 'Float32Array' || c === 'Float64Array') return `JS.newArray(${this.expr(args[0])}, 0.0)`;
    return `${sw}(${args.map((a: any) => this.expr(a)).join(', ')})`;
  }

  // ---------------------------------------------------------------- functions
  sigOf(node: any) {
    return this.checker.getSignatureFromDeclaration(node);
  }
  retType(node: any): string {
    // `const f: Fn = (...) => ...`: the declared function type wins over the inferred return
    if (node.parent && ts.isVariableDeclaration(node.parent) && node.parent.type) {
      const dsig = this.checker.getTypeFromTypeNode(node.parent.type).getCallSignatures?.()?.[0];
      if (dsig) return this.ty(this.checker.getReturnTypeOfSignature(dsig));
    }
    const s = this.sigOf(node);
    if (!s) return 'Void';
    return this.ty(this.checker.getReturnTypeOfSignature(s));
  }
  paramList(node: any, opts: {labels?: boolean} = {}): {decl: string; pre: string[]} {
    const pre: string[] = [];
    const ps = node.parameters.map((p: any, i: number) => {
      const pt = this.typeOf(p.name);
      let sw = this.ty(p.questionToken || p.initializer ? pt : pt);
      if (p.questionToken && !sw.endsWith('?')) sw += '?';
      let name: string;
      if (ts.isIdentifier(p.name)) name = esc(p.name.text);
      else {
        name = `_p${i}`;
        pre.push(...this.destructure(p.name, name, pt, false));
      }
      const s = ts.isIdentifier(p.name) ? this.checker.getSymbolAtLocation(p.name) : undefined;
      let inout = '';
      if (sw === this.cfg.typeMap['G'] && this.cfg.typeMap['G']) inout = 'inout ';
      if (s && this.inoutParams.has(s)) inout = 'inout ';
      if (s && this.shadowParams.has(s)) pre.push(`var ${name} = ${name}`);
      let def = '';
      if (p.initializer) def = ' = ' + this.as(p.initializer, sw.replace(/\?$/, ''));
      else if (p.questionToken) def = ' = nil';
      return `${opts.labels ? '' : '_ '}${name}: ${inout}${sw}${def}`;
    });
    return {decl: ps.join(', '), pre};
  }

  /** a function declaration (module or nested) */
  funcDecl(name: string, node: any, isStatic: boolean, access = '') {
    const ret = this.retType(node);
    const {decl, pre} = this.paramList(node);
    const r = ret === 'Void' ? '' : ` -> ${ret}`;
    this.w(`${access}${isStatic ? 'static ' : ''}func ${esc(name)}(${decl})${r} {`);
    this.ind++;
    for (const p of pre) this.w(p);
    this.fnStack.push({kind: 'func', ret});
    this.body(node.body, ret);
    this.fnStack.pop();
    this.ind--;
    this.w('}');
  }

  /** emits a function body (block or expression) */
  body(b: any, ret: string) {
    if (ts.isBlock(b)) {
      for (const s of b.statements) this.stmt(s);
      const last = b.statements[b.statements.length - 1];
      if (ret !== 'Void' && ret.endsWith('?') && (!last || !ts.isReturnStatement(last))) this.w('return nil');
      else if (this.cfg.ridge && ret !== 'Void' && last && ts.isSwitchStatement(last)) this.w('fatalError("unreachable")');
    } else {
      if (ret === 'Void') this.exprStmt(b);
      else this.w(`return ${this.retValue(b, ret)}`);
    }
  }
  retValue(e: any, ret: string): string {
    if (ret === 'Double' || ret === 'String' || ret === 'Bool') return this.as(e, ret);
    const u = this.unwrapParens(e);
    if (ts.isArrayLiteralExpression(u)) return this.arrayLit(u, ret.startsWith('[') ? ret : undefined);
    if (ts.isObjectLiteralExpression(u)) return this.objLit(u, ret.replace(/\?$/, ''));
    return this.expr(e, {want: ret});
  }

  /** an inline closure */
  closure(node: any, retOverride?: string): string {
    let rcs: any;
    if (this.cfg.ridge) {
      const ct = this.checker.getContextualType(node);
      const nn = ct ? this.checker.getNonNullableType(ct) : undefined;
      rcs = nn?.getCallSignatures?.()?.[0];
      if (!rcs && nn?.isUnion?.()) for (const x of nn.types) if ((rcs = x.getCallSignatures?.()?.[0])) break;
    }
    let ret: string;
    if (retOverride) ret = retOverride;
    else if (rcs) {
      ret = this.ty(this.checker.getReturnTypeOfSignature(rcs));
      if (ret === 'Void' && !(this.checker.getReturnTypeOfSignature(rcs).flags & ts.TypeFlags.Void)) ret = this.retType(node);
    } else ret = this.retType(node);
    const saved = this.lines, savedInd = this.ind;
    this.lines = [];
    this.ind = savedInd + 1;
    let {decl, pre} = this.paramList(node, {labels: true});
    let csig = rcs ?? this.checker.getContextualType(node)?.getCallSignatures?.()?.[0];
    if (!csig && node.parent && ts.isConditionalExpression(node.parent)) csig = this.typeOf(node.parent).getCallSignatures?.()?.[0];
    if (csig && csig.getParameters().length > node.parameters.length) {
      const extra = csig.getParameters().slice(node.parameters.length).map((p: any, i: number) => `_ _x${i}: ${this.ty(this.checker.getTypeOfSymbolAtLocation(p, p.valueDeclaration ?? node))}`);
      decl = [decl, ...extra].filter((x) => x).join(', ');
    }
    for (const p of pre) this.w(p);
    this.fnStack.push({kind: 'closure', ret});
    if (ts.isBlock(node.body)) this.body(node.body, ret);
    else if (ret === 'Void') this.exprStmt(node.body);
    else this.w(`return ${this.retValue(node.body, ret)}`);
    this.fnStack.pop();
    const inner = this.lines;
    this.lines = saved;
    this.ind = savedInd;
    const head = `{ (${decl}) -> ${ret} in`;
    return `${head}\n${inner.join('\n')}\n${'    '.repeat(savedInd)}}`;
  }

  // ---------------------------------------------------------------- calls
  call(e: any, o: {stmt?: boolean} = {}): string {
    const callee = e.expression;
    const args: any[] = [...e.arguments];
    if (this.cfg.callHook) {
      const h = this.cfg.callHook(this, e);
      if (h !== undefined) return h;
    }
    // IIFE
    const cu = this.unwrapParens(callee);
    if ((ts.isArrowFunction(cu) || ts.isFunctionExpression(cu)) && args.length === 0) {
      const ret = this.ty(this.typeOf(e));
      return `${this.closure(cu, ret)}()`;
    }
    if (ts.isIdentifier(callee)) {
      const n = callee.text;
      if (n === 'String') return this.as(args[0], 'String');
      if (n === 'Number') return this.as(args[0], 'Double');
      if (n === 'Boolean') return this.cond(args[0]);
      if (n === 'isFinite') return `${this.expr(args[0])}.isFinite`;
      if (n === 'isNaN') return `${this.expr(args[0])}.isNaN`;
      if (n === 'parseInt' || n === 'parseFloat') return `(Double(${this.expr(args[0])}) ?? .nan)`;
    }
    if (ts.isPropertyAccessExpression(callee)) {
      const obj = callee.expression;
      const m = callee.name.text;
      if (ts.isIdentifier(obj) && obj.text === 'Math') return this.mathCall(m, args);
      if (ts.isIdentifier(obj) && obj.text === 'Array' && m === 'from') return this.arrayFrom(e, args);
      if (ts.isIdentifier(obj) && obj.text === 'Object') return this.objectCall(e, m, args);
      if (ts.isIdentifier(obj) && obj.text === 'Number' && m === 'isFinite') return `${this.expr(args[0])}.isFinite`;
      if (ts.isIdentifier(obj) && obj.text === 'String' && m === 'fromCharCode') return `JS.fromCharCode(${this.expr(args[0])})`;
      const ot = this.nonNull(this.typeOf(obj));
      const osw = this.ty(ot);
      if (this.isArray(ot) || this.isTuple(ot)) {
        const r = this.arrayMethod(e, obj, m, args, ot, o);
        if (r !== undefined) return r;
      }
      if (this.isString(ot)) {
        const r = this.stringMethod(obj, m, args);
        if (r !== undefined) return r;
      }
      if (this.isNumber(ot)) {
        if (m === 'toFixed') return `JS.toFixed(${this.expr(obj)}, ${this.expr(args[0] ?? {kind: ts.SyntaxKind.NumericLiteral, text: '0'})})`;
        if (m === 'toString') return `JS.str(${this.expr(obj)})`;
      }
      if (osw.startsWith('JSMap') || osw.startsWith('JSSet')) {
        const os = this.expr(obj, {noForce: true});
        if (m === 'values' || m === 'keys' || m === 'entries') return `${os}.${m}`;
        if (m === 'get') return `${os}.get(${this.expr(args[0])})`;
        if (m === 'set') return `${os}.set(${this.expr(args[0])}, ${this.as(args[1], this.mapValueType(osw))})`;
        if (m === 'has') return `${os}.has(${this.expr(args[0])})`;
        if (m === 'add') return `${os}.add(${this.expr(args[0])})`;
        if (m === 'delete') return `${os}.delete(${this.expr(args[0])})`;
        if (m === 'clear') return `${os}.clear()`;
        if (m === 'forEach') return this.forEachToLoop(e, obj, args[0], true);
      }
    }
    // a user function: inout args where the parameter is G (or a mutated array)
    const sig = this.checker.getResolvedSignature(e);
    const decl = sig?.declaration;
    const params = decl?.parameters ?? [];
    let hasSpread = false;
    const parts: string[] = [];
    const pre: string[] = [];
    args.forEach((a: any, i: number) => {
      if (ts.isSpreadElement(a)) {
        hasSpread = true;
        const st = this.typeOf(a.expression);
        if (this.isTuple(st)) {
          const n = this.checker.getTypeArguments(st).length;
          const tv = this.fresh('_s');
          pre.push(`let ${tv} = ${this.expr(a.expression)}`);
          for (let j = 0; j < n; j++) parts.push(`${tv}.${j}`);
        } else {
          this.warn(a, 'array spread into call');
          parts.push(this.expr(a.expression));
        }
        return;
      }
      const p = params[Math.min(i, params.length - 1)];
      let s = this.argFor(a, p, i, e);
      parts.push(s);
    });
    // swift tail: board methods take Int flags
    const cs = this.calleeStr(callee);
    let callStr = `${cs}(${parts.join(', ')})`;
    if (this.cfg.intParams && ts.isPropertyAccessExpression(callee)) {
      const recvSw = this.ty(this.nonNull(this.typeOf(callee.expression)));
      const table = this.cfg.intParams[recvSw]?.[callee.name.text];
      const labels = this.cfg.labeledParams?.[recvSw]?.[callee.name.text];
      if (table || labels) {
        const fixed: string[] = [];
        let ai = 0;
        args.forEach((a: any, i: number) => {
          if (ts.isSpreadElement(a)) {
            const st = this.typeOf(a.expression);
            const n = this.checker.getTypeArguments(st).length;
            for (let j = 0; j < n; j++) fixed.push(parts[ai++]);
            return;
          }
          const pos = fixed.length;
          let v = parts[ai++];
          if (table?.includes(pos)) v = this.flag(a);
          if (labels?.[pos]) v = `${labels[pos]}: ${labels[pos] === 'coral' ? `${this.expr(a)}.map { Int($0) }` : v}`;
          fixed.push(v);
        });
        callStr = `${cs}(${fixed.join(', ')})`;
      }
    }
    if (hasSpread) {
      const ret = this.ty(this.typeOf(e));
      if (o.stmt) return `do { ${pre.join('; ')}; ${ret === 'Void' ? '' : '_ = '}${callStr} }`;
      return `{ () -> ${ret} in ${pre.join('; ')}; return ${callStr} }()`;
    }
    return callStr;
  }
  mapValueType(osw: string) {
    const inner = osw.slice(osw.indexOf('<') + 1, -1);
    const parts = splitTop(inner);
    return (parts[1] ?? 'Double').trim();
  }
  calleeStr(callee: any): string {
    if (ts.isPropertyAccessExpression(callee)) {
      const os = this.expr(callee.expression, {noForce: false});
      return `${this.wrap(os)}${callee.questionDotToken ? '?' : ''}.${esc(callee.name.text)}`;
    }
    return this.expr(callee);
  }
  argFor(a: any, p: any, i: number, call: any): string {
    void i;
    if (!p) return this.expr(a);
    const pt = this.typeOf(p.name);
    const sw = this.ty(pt);
    const ps = ts.isIdentifier(p.name) ? this.checker.getSymbolAtLocation(p.name) : undefined;
    const isG = this.cfg.typeMap['G'] && sw === this.cfg.typeMap['G'];
    if (isG || (ps && this.inoutParams.has(ps))) return `&${this.lvalue(a)}`;
    void call;
    const base = sw.replace(/\?$/, '');
    if (base === 'Double' || base === 'String' || base === 'Bool') return this.as(a, base);
    const u = this.unwrapParens(a);
    if (ts.isArrayLiteralExpression(u)) return this.arrayLit(u, base.startsWith('[') ? base : undefined);
    if (ts.isObjectLiteralExpression(u)) return this.objLit(u, base);
    if (ts.isArrowFunction(u) || ts.isFunctionExpression(u)) return this.closure(u);
    if (ts.isIdentifier(u)) return this.as(a, base.replace(/^@escaping /, ''));
    return this.expr(a, {want: base});
  }

  mathCall(m: string, args: any[]): string {
    if ((m === 'max' || m === 'min') && args.length === 1 && ts.isSpreadElement(args[0])) return `JS.${m}(${this.expr(args[0].expression)})`;
    if ((m === 'max' || m === 'min') && args.some((a: any) => ts.isSpreadElement(a))) {
      const parts = args.map((a: any) => (ts.isSpreadElement(a) ? `Array(${this.expr(a.expression)})` : `[${this.as(a, 'Double')}]`));
      return `JS.${m}(${parts.join(' + ')})`;
    }
    if (m === 'random') {
      this.warn(args[0] ?? this.sf, 'Math.random');
      return 'JS.random()';
    }
    return `JS.${m}(${args.map((a) => this.as(a, 'Double')).join(', ')})`;
  }
  arrayFrom(e: any, args: any[]): string {
    const a0 = this.unwrapParens(args[0]);
    const ret = this.ty(this.typeOf(e));
    const elT = ret.startsWith('[') ? ret.slice(1, -1) : 'Double';
    if (ts.isObjectLiteralExpression(a0)) {
      const lenP = a0.properties.find((p: any) => p.name?.text === 'length');
      const n = this.expr(lenP.initializer);
      if (!args[1]) return `JS.newArray(${n}, ${this.defaultOf(elT)})`;
      const cb = args[1];
      const iParam = cb.parameters[1];
      const iname = iParam && ts.isIdentifier(iParam.name) ? esc(iParam.name.text) : '_';
      const body = this.callbackBody(cb, elT, [`${iname === '_' ? '_' : iname}: Double`], ['Double']);
      return `JS.range(${n}).map ${body}`;
    }
    if (args[1]) return `Array(${this.expr(args[0])}).map ${this.closure(args[1])}`;
    const st = this.typeOf(args[0]);
    if (this.isString(st)) return `JS.chars(${this.expr(args[0])})`;
    return `Array(${this.expr(args[0])})`;
  }
  objectCall(e: any, m: string, args: any[]): string {
    if (m === 'keys') return `JS.keys(${this.expr(args[0])})`;
    if (m === 'values') return `JS.values(${this.expr(args[0])})`;
    if (m === 'entries') return `JS.entries(${this.expr(args[0])})`;
    if (m === 'assign') return this.expr(args[0]);
    if (m === 'freeze') return this.expr(args[0]);
    this.warn(e, `Object.${m}`);
    return this.expr(args[0]);
  }

  /**
   * A callback as a Swift closure, with explicit parameter types. The callback's first param binds
   * to the element (destructured when it is a pattern), the second to the index (Double).
   */
  callbackBody(cb: any, ret: string, params: string[], _pTypes: string[], pre: string[] = []): string {
    const saved = this.lines, savedInd = this.ind;
    this.lines = [];
    this.ind = savedInd + 1;
    for (const p of pre) this.w(p);
    this.fnStack.push({kind: 'closure', ret});
    const cbu = this.unwrapParens(cb);
    if (ts.isArrowFunction(cbu) || ts.isFunctionExpression(cbu)) {
      if (ts.isBlock(cbu.body)) this.body(cbu.body, ret);
      else if (ret === 'Void') this.exprStmt(cbu.body);
      else this.w(`return ${this.retValue(cbu.body, ret)}`);
    } else {
      // a function reference: call it with the element
      this.w(`return ${this.expr(cb)}(${params.map((p) => p.split(':')[0]).join(', ')})`);
    }
    this.fnStack.pop();
    const inner = this.lines;
    this.lines = saved;
    this.ind = savedInd;
    return `{ (${params.join(', ')}) -> ${ret} in\n${inner.join('\n')}\n${'    '.repeat(savedInd)}}`;
  }

  /** element param of a callback: name + destructuring prelude */
  cbParam(cb: any, idx: number, elSw: string, elT: any): {name: string; pre: string[]} {
    const p = cb.parameters?.[idx];
    if (!p) return {name: '_', pre: []};
    if (ts.isIdentifier(p.name)) return {name: esc(p.name.text), pre: []};
    const tmp = this.fresh('_e');
    void elSw;
    return {name: tmp, pre: this.destructure(p.name, tmp, elT, false)};
  }

  arrayMethod(e: any, obj: any, m: string, args: any[], ot: any, o: {stmt?: boolean}): string | undefined {
    const tupN = this.isTuple(ot) ? this.checker.getTypeArguments(ot).length : 0;
    const elT = this.isArray(ot) ? this.elemType(ot) : tupN ? this.checker.getTypeArguments(ot)[0] : undefined;
    const elSw = elT ? this.ty(elT) : 'Double';
    const os = () => (tupN ? `JS.arr(${this.expr(obj)})` : this.expr(obj));
    const cb = args[0];
    const cbu = cb ? this.unwrapParens(cb) : undefined;
    const isFn = cbu && (ts.isArrowFunction(cbu) || ts.isFunctionExpression(cbu));
    const usesIndex = isFn && cbu.parameters.length >= 2;
    const mkCb = (ret: string) => {
      if (cbu && ts.isIdentifier(cbu) && cbu.text === 'Boolean') return `{ (x: ${elSw}) -> Bool in JS.truthy(x) }`;
      if (!isFn) return `{ (x: ${elSw}) -> ${ret} in ${this.expr(cb)}(x) }`;
      const ep = this.cbParam(cbu, 0, elSw, elT);
      if (usesIndex) {
        const ip = cbu.parameters[1];
        const iname = ts.isIdentifier(ip.name) ? esc(ip.name.text) : '_';
        return this.callbackBody(cbu, ret, [`_ie: (offset: Int, element: ${elSw})`], [], [`let ${ep.name === '_' ? '_' : ep.name} = _ie.element`, `let ${iname} = Double(_ie.offset)`, ...ep.pre].filter((x) => !x.startsWith('let _ =')));
      }
      return this.callbackBody(cbu, ret, [`${ep.name}: ${elSw}`], [], ep.pre);
    };
    const enumd = () => (usesIndex ? `${this.wrap(os())}.enumerated()` : os());
    if (tupN && m === 'map') return `JS.tuple${tupN}(${enumd()}.map ${mkCb(elSw)})`;
    switch (m) {
      case 'push': {
        const ou = this.unwrapParens(obj);
        if (ts.isConditionalExpression(ou)) {
          const one = (side: any) => {
            const t = this.lvalue(side);
            return args.map((a: any) => (ts.isSpreadElement(a) ? `${t}.append(contentsOf: ${this.arrOf(a.expression, `[${elSw}]`)})` : `${t}.append(${this.elemValue(a, elSw)})`)).join('; ');
          };
          return `if ${this.cond(ou.condition)} { ${one(ou.whenTrue)} } else { ${one(ou.whenFalse)} }`;
        }
        const target = this.lvalue(obj);
        const items = args.map((a: any) => {
          if (ts.isSpreadElement(a)) return {spread: true, s: this.arrOf(a.expression, `[${elSw}]`)};
          return {spread: false, s: this.elemValue(a, elSw)};
        });
        if (!o.stmt) this.warn(e, 'push in expression');
        if (items.length === 1 && !items[0].spread) return `${target}.append(${items[0].s})`;
        return items.map((it) => (it.spread ? `${target}.append(contentsOf: ${it.s})` : `${target}.append(${it.s})`)).join('; ');
      }
      case 'forEach':
        return this.forEachToLoop(e, obj, cb, false);
      case 'map': {
        const ret = this.ty(this.elemType(this.typeOf(e)) ?? elT);
        return `${enumd()}.map ${mkCb(ret)}`;
      }
      case 'filter':
        return usesIndex ? `${enumd()}.filter ${mkCb('Bool')}.map { $0.element }` : `${os()}.filter ${mkCb('Bool')}`;
      case 'some':
        return `${enumd()}.contains(where: ${mkCb('Bool')})`;
      case 'every':
        return `${enumd()}.allSatisfy(${mkCb('Bool')})`;
      case 'find':
        return `${os()}.first(where: ${mkCb('Bool')})`;
      case 'findIndex':
        return `JS.findIndex(${os()}, ${mkCb('Bool')})`;
      case 'reduce': {
        const accT = this.ty(this.typeOf(e));
        const init = args[1] ? ((ts.isArrayLiteralExpression(args[1]) && args[1].elements.length === 0) ? `([] as ${accT})` : this.as(args[1], accT)) : undefined;
        const f = cbu;
        const accP = f.parameters[0], elP = f.parameters[1], iP = f.parameters[2], arrP = f.parameters[3];
        const accName = ts.isIdentifier(accP.name) ? esc(accP.name.text) : '_acc';
        const ep = elP ? this.cbParam(f, 1, elSw, elT) : {name: '_', pre: []};
        if (!init) this.warn(e, 'reduce without initial value');
        if (iP) {
          const iname = ts.isIdentifier(iP.name) ? esc(iP.name.text) : '_';
          if (arrP && ts.isIdentifier(arrP.name)) {
            const an = esc(arrP.name.text);
            return `({ (${an}: [${elSw}]) -> ${accT} in ${an}.enumerated().reduce(${init}) ${this.callbackBody(f, accT, [`${accName}: ${accT}`, `_ie: (offset: Int, element: ${elSw})`], [], [`let ${ep.name} = _ie.element`, `let ${iname} = Double(_ie.offset)`, ...ep.pre])} })(${os()})`;
          }
          return `${this.wrap(os())}.enumerated().reduce(${init}) ${this.callbackBody(f, accT, [`${accName}: ${accT}`, `_ie: (offset: Int, element: ${elSw})`], [], [`let ${ep.name} = _ie.element`, `let ${iname} = Double(_ie.offset)`, ...ep.pre])}`;
        }
        return `${os()}.reduce(${init}) ${this.callbackBody(f, accT, [`${accName}: ${accT}`, `${ep.name}: ${elSw}`], [], ep.pre)}`;
      }
      case 'slice':
        return `JS.slice(${os()}${args.map((a: any) => ', ' + this.as(a, 'Double')).join('')})`;
      case 'concat':
        return '(' + [os(), ...args.map((a: any) => this.arrOf(a, `[${elSw}]`))].join(' + ') + ')';
      case 'includes':
        return `${os()}.contains(${this.elemValue(args[0], elSw)})`;
      case 'indexOf':
        return `JS.indexOf(${os()}, ${this.elemValue(args[0], elSw)})`;
      case 'join':
        return `${os()}.map { JS.str($0) }.joined(separator: ${args[0] ? this.expr(args[0]) : '","'})`;
      case 'reverse':
        if (o.stmt) return `${this.lvalue(obj)}.reverse()`;
        return `Array(${os()}.reversed())`;
      case 'sort': {
        const c = this.callbackBody(cbu, 'Double', [`${this.cbParam(cbu, 0, elSw, elT).name}: ${elSw}`, `${this.cbParam(cbu, 1, elSw, elT).name}: ${elSw}`], [], [...this.cbParam(cbu, 0, elSw, elT).pre, ...this.cbParam(cbu, 1, elSw, elT).pre]);
        const u = this.unwrapParens(obj);
        if (o.stmt && (ts.isIdentifier(u) || ts.isPropertyAccessExpression(u))) return `JS.sort(&${this.lvalue(obj)}, ${c})`;
        return `JS.sorted(${os()}, ${c})`;
      }
      case 'fill':
        return `JS.newArray(Double(${os()}.count), ${this.elemValue(args[0], elSw)})`;
      case 'pop':
        return `${this.lvalue(obj)}.removeLast()`;
      case 'shift':
        return `${this.lvalue(obj)}.removeFirst()`;
      case 'at':
        return `JS.atIndex(${os()}, ${this.expr(args[0])})`;
      case 'flat': {
        const inner = elT && this.isTuple(elT) ? this.checker.getTypeArguments(elT).length : 0;
        if (inner > 0) return `${os()}.flatMap { [${Array.from({length: inner}, (_, i) => `$0.${i}`).join(', ')}] }`;
        return `${os()}.flatMap { $0 }`;
      }
      case 'flatMap':
        return `${os()}.flatMap ${mkCb(this.ty(this.typeOf(e)))}`;
    }
    return undefined;
  }

  stringMethod(obj: any, m: string, args: any[]): string | undefined {
    const os = this.expr(obj);
    switch (m) {
      case 'split':
        if (args[0] && ts.isStringLiteral(args[0]) && args[0].text === '') return `JS.chars(${os})`;
        return `JS.split(${os}, ${this.expr(args[0])})`;
      case 'includes':
        return `${this.wrap(os)}.contains(${this.expr(args[0])})`;
      case 'indexOf':
        return `JS.indexOf(${os}, ${this.expr(args[0])})`;
      case 'padStart':
        return `JS.padStart(${os}, ${this.as(args[0], 'Double')}, ${args[1] ? this.expr(args[1]) : '" "'})`;
      case 'padEnd':
        return `JS.padEnd(${os}, ${this.as(args[0], 'Double')}, ${args[1] ? this.expr(args[1]) : '" "'})`;
      case 'toUpperCase':
        return `${this.wrap(os)}.uppercased()`;
      case 'toLowerCase':
        return `${this.wrap(os)}.lowercased()`;
      case 'charCodeAt':
        return `JS.charCodeAt(${os}, ${args[0] ? this.expr(args[0]) : '0'})`;
      case 'slice':
      case 'substring':
        return `JS.sliceStr(${os}${args.map((a: any) => ', ' + this.as(a, 'Double')).join('')})`;
      case 'repeat':
        return `String(repeating: ${os}, count: ${this.int(args[0])})`;
      case 'trim':
        return `JS.trim(${os})`;
      case 'startsWith':
        return `${this.wrap(os)}.hasPrefix(${this.expr(args[0])})`;
      case 'endsWith':
        return `${this.wrap(os)}.hasSuffix(${this.expr(args[0])})`;
      case 'replace':
        return `JS.replace(${os}, ${this.expr(args[0])}, ${this.expr(args[1])})`;
      case 'toString':
        return os;
    }
    return undefined;
  }

  /** `arr.forEach(cb)` as a labelled for-loop; returns '' (it writes lines itself) */
  forEachToLoop(e: any, obj: any, cb: any, isMap: boolean): string {
    const ot = this.nonNull(this.typeOf(obj));
    const cbu = this.unwrapParens(cb);
    let seq: string;
    let elT: any;
    if (this.isString(ot)) {
      seq = `JS.chars(${this.expr(obj)})`;
      elT = ot;
    } else if (isMap) {
      seq = `${this.expr(obj)}.entries`;
      elT = undefined;
    } else {
      seq = this.expr(obj);
      elT = this.isArray(ot) ? this.elemType(ot) : undefined;
    }
    const label = this.fresh('fe');
    const usesIndex = cbu.parameters.length >= 2;
    const ep = this.cbParam(cbu, 0, elT ? this.ty(elT) : 'Double', elT);
    if (usesIndex) {
      const ip = cbu.parameters[1];
      const iname = ts.isIdentifier(ip.name) ? esc(ip.name.text) : '_';
      this.w(`${label}: for (_ii, ${ep.name}) in ${this.wrap(seq)}.enumerated() {`);
      this.ind++;
      if (iname !== '_') this.w(`let ${iname} = Double(_ii)`);
    } else {
      this.w(`${label}: for ${ep.name} in ${seq} {`);
      this.ind++;
    }
    for (const p of ep.pre) this.w(p);
    this.fnStack.push({kind: 'closure', ret: 'Void', feLabel: label});
    if (ts.isBlock(cbu.body)) for (const s of cbu.body.statements) this.stmt(s);
    else this.exprStmt(cbu.body);
    this.fnStack.pop();
    this.ind--;
    this.w('}');
    void e;
    return '';
  }

  // ---------------------------------------------------------------- destructuring
  /** returns lines binding the names in `pat` from the Swift expression `src` (of TS type t) */
  destructure(pat: any, src: string, t: any, mutable: boolean, kw?: string): string[] {
    const out: string[] = [];
    const k = kw ?? (mutable ? 'var' : 'let');
    if (ts.isArrayBindingPattern(pat)) {
      const tup = t && this.isTuple(this.nonNull(t));
      const args = tup ? this.checker.getTypeArguments(this.nonNull(t)) : [];
      pat.elements.forEach((el: any, i: number) => {
        if (ts.isOmittedExpression(el)) return;
        const acc = tup ? `${src}.${i}` : `${src}[${i}]`;
        const et = tup ? args[i] : t && this.isArray(this.nonNull(t)) ? this.elemType(this.nonNull(t)) : undefined;
        if (el.dotDotDotToken) {
          out.push(`${k} ${esc(el.name.text)} = JS.slice(${src}, ${i})`);
          return;
        }
        if (ts.isIdentifier(el.name)) {
          const vk = kw ?? (this.isMutated(el.name) ? 'var' : 'let');
          let v = acc;
          if (el.initializer) v = `(${acc} ?? ${this.expr(el.initializer)})`;
          out.push(`${vk} ${esc(el.name.text)}: ${this.ty(this.typeOf(el.name))} = ${v}`);
        } else {
          const tmp = this.fresh('_d');
          out.push(`let ${tmp} = ${acc}`);
          out.push(...this.destructure(el.name, tmp, et, mutable, kw));
        }
      });
    } else if (ts.isObjectBindingPattern(pat)) {
      for (const el of pat.elements) {
        const key = el.propertyName ? propName(el.propertyName) : el.name.text;
        const ot = t ? this.nonNull(t) : undefined;
        const osw = ot ? this.ty(ot) : '';
        const acc = osw.startsWith('[String:') ? `${src}[${JSON.stringify(key)}]!` : `${src}.${esc(key)}`;
        if (ts.isIdentifier(el.name)) {
          const vk = kw ?? (this.isMutated(el.name) ? 'var' : 'let');
          let v = acc;
          if (el.initializer) v = `(${acc} ?? ${this.expr(el.initializer)})`;
          out.push(`${vk} ${esc(el.name.text)}: ${this.ty(this.typeOf(el.name))} = ${v}`);
        } else {
          const tmp = this.fresh('_d');
          out.push(`let ${tmp} = ${acc}`);
          out.push(...this.destructure(el.name, tmp, undefined, mutable, kw));
        }
      }
    }
    return out;
  }

  // ---------------------------------------------------------------- statements
  stmt(s: any) {
    const K = ts.SyntaxKind;
    switch (s.kind) {
      case K.VariableStatement:
        return this.varStmt(s.declarationList, false);
      case K.ExpressionStatement:
        return this.exprStmt(s.expression);
      case K.IfStatement:
        return this.ifStmt(s, false);
      case K.ForStatement:
        return this.forStmt(s);
      case K.ForOfStatement:
        return this.forOf(s);
      case K.ForInStatement:
        return this.forIn(s);
      case K.WhileStatement:
        this.w(`while ${this.cond(s.expression)} {`);
        this.blockBody(s.statement);
        this.w('}');
        return;
      case K.DoStatement:
        this.w('repeat {');
        this.blockBody(s.statement);
        this.w(`} while ${this.cond(s.expression)}`);
        return;
      case K.ReturnStatement:
        return this.returnStmt(s);
      case K.BreakStatement:
        this.w(s.label ? `break ${s.label.text}` : 'break');
        return;
      case K.ContinueStatement:
        this.w(s.label ? `continue ${s.label.text}` : 'continue');
        return;
      case K.Block:
        this.w('do {');
        this.ind++;
        for (const x of s.statements) this.stmt(x);
        this.ind--;
        this.w('}');
        return;
      case K.LabeledStatement: {
        const inner = s.statement;
        const before = this.lines.length;
        this.stmt(inner);
        // put the label on the first loop line emitted
        for (let i = before; i < this.lines.length; i++) {
          const m = this.lines[i].match(/^(\s*)(while|for|repeat)\b/);
          if (m) {
            this.lines[i] = `${m[1]}${s.label.text}: ${this.lines[i].trimStart()}`;
            break;
          }
        }
        return;
      }
      case K.FunctionDeclaration:
        return this.funcDecl(s.name.text, s, false);
      case K.EmptyStatement:
        return;
      case K.SwitchStatement:
        return this.switchStmt(s);
      case K.TypeAliasDeclaration:
      case K.InterfaceDeclaration:
        return;
      case K.ThrowStatement:
        this.w(`fatalError("${s.getText().replace(/"/g, "'")}")`);
        return;
      default:
        this.warn(s, `unsupported statement ${K[s.kind]}`);
        this.w(`// ? ${K[s.kind]}`);
    }
  }
  blockBody(b: any) {
    this.ind++;
    if (ts.isBlock(b)) for (const x of b.statements) this.stmt(x);
    else this.stmt(b);
    this.ind--;
  }
  ifStmt(s: any, isElse: boolean) {
    this.w(`${isElse ? '} else ' : ''}if ${this.cond(s.expression)} {`);
    this.blockBody(s.thenStatement);
    if (s.elseStatement) {
      if (ts.isIfStatement(s.elseStatement)) {
        this.ifStmt(s.elseStatement, true);
        return;
      }
      this.w('} else {');
      this.blockBody(s.elseStatement);
    }
    this.w('}');
  }
  switchStmt(s: any) {
    this.w(`switch ${this.expr(s.expression)} {`);
    for (const c of s.caseBlock.clauses) {
      if (ts.isCaseClause(c)) this.w(`case ${this.expr(c.expression)}:`);
      else this.w('default:');
      this.ind++;
      const stmts = c.statements.filter((x: any) => !ts.isBreakStatement(x));
      if (stmts.length === 0) this.w('break');
      for (const x of stmts) this.stmt(x);
      this.ind--;
    }
    if (!s.caseBlock.clauses.some((c: any) => ts.isDefaultClause(c))) this.w('default: break');
    this.w('}');
  }
  returnStmt(s: any) {
    const f = this.fn;
    if (f?.feLabel) {
      this.w(`continue ${f.feLabel}`);
      return;
    }
    if (f?.isDraw) {
      if (!s.expression) this.w('return .none');
      else this.w(`return ${this.retValue(s.expression, 'SceneOut')}`);
      return;
    }
    if (!s.expression) {
      this.w(f.ret && f.ret !== 'Void' && f.ret.endsWith('?') ? 'return nil' : 'return');
      return;
    }
    if (f.ret === 'Void') {
      this.exprStmt(s.expression);
      this.w('return');
      return;
    }
    this.w(`return ${this.retValue(s.expression, f.ret)}`);
  }

  varStmt(list: any, isModule: boolean) {
    const isConst = (list.flags & ts.NodeFlags.Const) !== 0;
    for (const d of list.declarations) {
      const init = d.initializer;
      if (ts.isIdentifier(d.name)) {
        const name = d.name.text;
        const iu = init ? this.unwrapParens(init) : undefined;
        if (iu && (ts.isArrowFunction(iu) || ts.isFunctionExpression(iu)) && isConst) {
          this.funcDecl(name, iu, isModule);
          continue;
        }
        const t = this.typeOf(d.name);
        let sw = this.ty(t);
        // `const R = F5[k] ?? null`: TS drops the null (unchecked index), Swift keeps it optional
        if (iu && ts.isBinaryExpression(iu) && iu.operatorToken.kind === ts.SyntaxKind.QuestionQuestionToken && !sw.endsWith('?')) {
          const ru = this.unwrapParens(iu.right);
          if (ru.kind === ts.SyntaxKind.NullKeyword || (ts.isIdentifier(ru) && ru.text === 'undefined')) {
            sw += '?';
            this.optSyms.add(this.checker.getSymbolAtLocation(d.name));
          }
        }
        const mut = !isConst || this.isMutated(d.name);
        const kw = isModule ? (mut && !isConst ? 'nonisolated(unsafe) static var' : 'static let') : mut ? 'var' : 'let';
        if (!init) {
          this.w(`${kw} ${esc(name)}: ${sw}${sw.endsWith('?') ? ' = nil' : ''}`);
          continue;
        }
        this.w(`${kw} ${esc(name)}: ${sw} = ${this.initValue(init, sw)}`);
      } else {
        const t = this.typeOf(d.name);
        const tmp = this.fresh('_d');
        this.w(`${isModule ? 'static let' : 'let'} ${tmp} = ${this.expr(init)}`);
        for (const l of this.destructure(d.name, tmp, this.typeOf(init) ?? t, !isConst, isModule ? 'static let' : undefined)) this.w(l);
      }
    }
  }
  initValue(init: any, sw: string): string {
    const base = sw.replace(/\?$/, '');
    if (base === 'Double' || base === 'String' || base === 'Bool') return this.as(init, base);
    const u = this.unwrapParens(init);
    if (ts.isArrayLiteralExpression(u)) return this.arrayLit(u, base.startsWith('[') ? base : undefined);
    if (ts.isObjectLiteralExpression(u)) return this.objLit(u, base);
    return this.expr(init, {want: base});
  }

  exprStmt(e: any) {
    const K = ts.SyntaxKind;
    const u = this.unwrapParens(e);
    if (ts.isBinaryExpression(u)) {
      const k = u.operatorToken.kind;
      if (k === K.CommaToken) {
        this.exprStmt(u.left);
        this.exprStmt(u.right);
        return;
      }
      if (k === K.AmpersandAmpersandToken) {
        this.w(`if ${this.cond(u.left)} {`);
        this.ind++;
        this.exprStmt(u.right);
        this.ind--;
        this.w('}');
        return;
      }
      if (k === K.BarBarToken) {
        this.w(`if !${this.wrap(this.cond(u.left))} {`);
        this.ind++;
        this.exprStmt(u.right);
        this.ind--;
        this.w('}');
        return;
      }
      if (k === K.EqualsToken) {
        const L = this.unwrapParens(u.left);
        if (ts.isPropertyAccessExpression(L) && L.name.text === 'length') {
          this.w(`JS.setLength(&${this.lvalue(L.expression)}, ${this.as(u.right, 'Double')})`);
          return;
        }
        if (ts.isArrayLiteralExpression(L)) {
          // [a, b] = [b, a]
          const tmp = this.fresh('_d');
          this.w(`let ${tmp} = ${this.expr(u.right)}`);
          const tup = this.isTuple(this.typeOf(u.right));
          L.elements.forEach((el: any, i: number) => {
            if (ts.isOmittedExpression(el)) return;
            this.w(`${this.lvalue(el)} = ${tup ? `${tmp}.${i}` : `${tmp}[${i}]`}`);
          });
          return;
        }
      }
    }
    if (ts.isConditionalExpression(u)) {
      this.w(`if ${this.cond(u.condition)} {`);
      this.ind++;
      this.exprStmt(u.whenTrue);
      this.ind--;
      this.w('} else {');
      this.ind++;
      this.exprStmt(u.whenFalse);
      this.ind--;
      this.w('}');
      return;
    }
    if ((ts.isPostfixUnaryExpression(u) || ts.isPrefixUnaryExpression(u)) && (u.operator === K.PlusPlusToken || u.operator === K.MinusMinusToken)) {
      this.w(`${this.lvalue(u.operand)} ${u.operator === K.PlusPlusToken ? '+=' : '-='} 1`);
      return;
    }
    if (ts.isVoidExpression(u)) return;
    if (ts.isCallExpression(u)) {
      const s = this.call(u, {stmt: true});
      if (s === '') return;
      const rt = this.typeOf(u);
      const isVoid = rt.flags & (ts.TypeFlags.Void | ts.TypeFlags.Undefined);
      const m = ts.isPropertyAccessExpression(u.expression) ? u.expression.name.text : '';
      const discard = !isVoid && !['push', 'sort', 'set', 'add', 'delete', 'reverse', 'forEach', 'clear'].includes(m) && !s.includes('.append(') && !s.startsWith('JS.sort(');
      for (const line of s.split('\n')) void line;
      this.w(discard ? `_ = ${s}` : s);
      return;
    }
    if (ts.isIdentifier(u) || ts.isPropertyAccessExpression(u)) return;
    this.w(this.expr(e, {stmt: true}));
  }

  forStmt(s: any) {
    // for (init; cond; inc) body  ->  do { var i = a; while cond { defer { inc }; body } }
    this.w('do {');
    this.ind++;
    if (s.initializer) {
      if (ts.isVariableDeclarationList(s.initializer)) {
        for (const d of s.initializer.declarations) {
          const sw = this.ty(this.typeOf(d.name));
          const mut = this.isMutated(d.name);
          this.w(`${mut ? 'var' : 'let'} ${esc(d.name.text)}: ${sw}${d.initializer ? ' = ' + this.initValue(d.initializer, sw) : ''}`);
        }
      } else this.exprStmt(s.initializer);
    }
    this.w(`while ${s.condition ? this.cond(s.condition) : 'true'} {`);
    this.ind++;
    if (s.incrementor) {
      const saved = this.lines;
      this.lines = [];
      const ind = this.ind;
      this.ind = 0;
      this.exprStmt(s.incrementor);
      const inc = this.lines;
      this.lines = saved;
      this.ind = ind;
      this.w(`defer { ${inc.join('; ')} }`);
    }
    const b = s.statement;
    if (ts.isBlock(b)) for (const x of b.statements) this.stmt(x);
    else this.stmt(b);
    this.ind--;
    this.w('}');
    this.ind--;
    this.w('}');
  }

  forOf(s: any) {
    const it = s.expression;
    const itT = this.nonNull(this.typeOf(it));
    let seq: string;
    let elT: any;
    let tupleFor = false;
    if (this.isString(itT)) {
      seq = `JS.chars(${this.expr(it)})`;
      elT = itT;
    } else {
      const u = this.unwrapParens(it);
      let force: string | undefined;
      const d0 = s.initializer.declarations[0];
      if (ts.isArrayLiteralExpression(u)) {
        const lt = this.typeOf(u);
        if (ts.isArrayBindingPattern(d0.name) && u.elements.length > 0 && u.elements.every((x: any) => ts.isArrayLiteralExpression(x) && x.elements.length === d0.name.elements.length)) {
          const first = u.elements[0];
          tupleFor = true;
          force = '[(' + first.elements.map((y: any) => this.ty(this.checker.getBaseTypeOfLiteralType(this.typeOf(y)))).join(', ') + ')]';
        } else if (this.isArray(lt)) force = this.ty(lt);
      }
      seq = ts.isArrayLiteralExpression(u) ? this.arrayLit(u, force) : this.expr(it);
      elT = this.isArray(itT) ? this.elemType(itT) : this.isTuple(itT) ? undefined : undefined;
      if (ts.isArrayLiteralExpression(u)) {
        const lt = this.typeOf(u);
        elT = this.isArray(lt) ? this.elemType(lt) : elT;
      }
    }
    const d = s.initializer.declarations[0];
    if (ts.isIdentifier(d.name)) {
      const mut = this.isMutated(d.name);
      this.w(`for ${mut ? 'var ' : ''}${esc(d.name.text)} in ${seq} {`);
      this.ind++;
    } else {
      const tmp = this.fresh('_e');
      this.w(`for ${tmp} in ${seq} {`);
      this.ind++;
      if (tupleFor) {
        d.name.elements.forEach((el: any, i: number) => {
          if (ts.isOmittedExpression(el)) return;
          this.w(`${this.isMutated(el.name) ? 'var' : 'let'} ${esc(el.name.text)}: ${this.ty(this.typeOf(el.name))} = ${tmp}.${i}`);
        });
      } else for (const l of this.destructure(d.name, tmp, elT, false)) this.w(l);
    }
    this.fnStack.push({...this.fn, feLabel: undefined});
    const b = s.statement;
    if (ts.isBlock(b)) for (const x of b.statements) this.stmt(x);
    else this.stmt(b);
    this.fnStack.pop();
    this.ind--;
    this.w('}');
  }
  forIn(s: any) {
    const d = s.initializer.declarations[0];
    this.w(`for ${esc(d.name.text)} in JS.keys(${this.expr(s.expression)}) {`);
    this.blockBody(s.statement);
    this.w('}');
  }
}

// ------------------------------------------------------------------ utils
export function splitTop(s: string): string[] {
  const out: string[] = [];
  let depth = 0, cur = '';
  for (const ch of s) {
    if (ch === '(' || ch === '[' || ch === '<') depth++;
    if (ch === ')' || ch === ']' || ch === '>') depth--;
    if (ch === ',' && depth === 0) {
      out.push(cur.trim());
      cur = '';
    } else cur += ch;
  }
  if (cur.trim()) out.push(cur.trim());
  return out;
}
function balanced(s: string) {
  let d = 0;
  for (const ch of s) {
    if (ch === '(') d++;
    if (ch === ')') {
      d--;
      if (d < 0) return false;
    }
  }
  return d === 0;
}
function strEsc(s: string) {
  return s.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n');
}
export function propName(n: any): string {
  if (ts.isIdentifier(n) || ts.isStringLiteral(n) || ts.isNumericLiteral(n) || ts.isPrivateIdentifier?.(n)) return n.text;
  if (ts.isComputedPropertyName(n)) return n.expression.getText();
  return n.getText();
}

// ------------------------------------------------------------------ Matrix mode
const capital = (s: string) => s[0].toUpperCase() + s.slice(1);

function matrixConfig(enumName: string): Config {
  const boardInts: Record<string, number[]> = {on: [3], fr: [3], fs: [3], line: [5], ring: [4], disc: [4], rect: [6]};
  return {
    enumName,
    typeMap: {Tgt: 'MXTgt', G: 'MatrixBoard', MC: 'MatrixContext', MOut: 'SceneOut', MScn: 'MatrixScene', Opts: 'MatrixDealOptions', MHap: '[HapticCue]', '{kind,t}': 'HapticCue', '{atgym,countdown,setupDone,stillLeft}': 'MatrixLiveData', '{day,sessions,week}': 'MatrixDayData'},
    importMap: {
      PROOF: 'PROOF', TAU: 'TAU', COLS: 'Double(COLS)', ROWS: 'Double(ROWS)', ICON: 'MXJS.ICON', iconW: 'MXJS.iconW', iconH: 'MXJS.iconH',
      textWidth: 'MXJS.textWidth', text: 'MXJS.text', lastRing: 'lastRingWeb',
    },
    intParams: {MatrixBoard: boardInts},
    labeledParams: {MatrixBoard: {num: {5: 'dim', 6: 'coral'}}},
    valueTypes: new Set(['MatrixBoard']),
    propHook: (em, node, os) => {
      if (!ts.isPropertyAccessExpression(node)) return undefined;
      const s = em.checker.getSymbolAtLocation(node.name);
      const d = s?.valueDeclaration ?? s?.declarations?.[0];
      if (!d) return undefined;
      const file = path.basename(d.getSourceFile().fileName);
      if (file !== 'mxlib.ts') return undefined;
      const n = node.name.text;
      // MC fields that are Int / enum in Swift
      let p = d.parent;
      while (p && !ts.isTypeAliasDeclaration(p)) p = p.parent;
      if (p?.name?.text === 'MC') {
        if (['N', 'day', 'week', 'sessions'].includes(n)) return `Double(${em.wrap(os)}.${n})`;
        if (n === 'pos') return `${em.wrap(os)}.pos.rawValue`;
      }
      return undefined;
    },
    objHook: (em, node, sw) => {
      const props: Record<string, any> = {};
      for (const p of node.properties) {
        if (ts.isPropertyAssignment(p)) props[propName(p.name)] = p.initializer;
        else if (ts.isShorthandPropertyAssignment(p)) props[p.name.text] = p.name;
        else if (ts.isMethodDeclaration(p)) props[propName(p.name)] = p;
      }
      if (sw === 'SceneOut') {
        const a: string[] = [];
        if (props.ph !== undefined) a.push(`phase: ${em.as(props.ph, 'String')}`);
        if (props.o !== undefined) {
          const ou = em.unwrapParens(props.o);
          a.push(`opts: ${ts.isObjectLiteralExpression(ou) ? em.objLit(ou, 'MatrixDealOptions') : em.expr(props.o)}`);
        }
        if (props.flash !== undefined) a.push(`flash: ${em.as(props.flash, 'Double')}`);
        if (props.shake !== undefined) a.push(`shake: ${em.as(props.shake, 'Double')}`);
        return `SceneOut(${a.join(', ')})`;
      }
      if (sw === 'MatrixDealOptions') {
        const a: string[] = [];
        for (const k of ['stagger', 'scatter', 'burst']) if (props[k] !== undefined) a.push(`${k}: ${em.as(props[k], 'Double')}`);
        for (const k of Object.keys(props)) if (!['stagger', 'scatter', 'burst'].includes(k)) em.warn(node, `Opts.${k} not supported`);
        return `MatrixDealOptions(${a.join(', ')})`;
      }
      if (sw === 'HapticCue') {
        const kind = em.unwrapParens(props.kind);
        const ks = ts.isStringLiteral(kind) ? `.${kind.text}` : `HapticKind(rawValue: ${em.as(props.kind, 'String')})!`;
        return `HapticCue(t: ${em.as(props.t, 'Double')}, kind: ${ks})`;
      }
      if (sw === 'MatrixScene') {
        const hap = props.hap !== undefined ? `haptics: ${em.initValue(props.hap, '[HapticCue]')}` : '';
        const dr = props.draw;
        return `MatrixScene(${hap}) ${em.drawClosure(dr)}`;
      }
      return undefined;
    },
    callHook: (em, node) => {
      const callee = node.expression;
      // icon(g, 'bell', ...): MX.icon with the enum key
      if (ts.isIdentifier(callee) && callee.text === 'text') {
        const s = em.checker.getSymbolAtLocation(callee);
        const d = s && (s.flags & ts.SymbolFlags.Alias ? em.checker.getAliasedSymbol(s) : s)?.valueDeclaration;
        if (d && path.basename(d.getSourceFile().fileName) === 'dots.ts') {
          const [s0, x0, y0, opts] = node.arguments;
          let extra = '';
          if (opts) {
            const ou = em.unwrapParens(opts);
            for (const p of ou.properties) {
              const k = ts.isShorthandPropertyAssignment(p) ? p.name.text : propName(p.name);
              const v = ts.isShorthandPropertyAssignment(p) ? p.name : p.initializer;
              extra += `, ${k}: ${k === 'coral' ? `${em.expr(v)}.map { Int($0) }` : em.as(v, 'Double')}`;
            }
          }
          return `MXJS.text(${em.as(s0, 'String')}, ${em.as(x0, 'Double')}, ${em.as(y0, 'Double')}${extra})`;
        }
      }
      if (ts.isIdentifier(callee) && callee.text === 'textWidth') {
        const [s0, sc] = node.arguments;
        return `MatrixLED.textWidth(${em.as(s0, 'String')}${sc ? `, scale: ${em.as(sc, 'Double')}` : ''})`;
      }
      return undefined;
    },
  };
}

// ------------------------------------------------------------------ ridge mode
/** builder classes (RidgeTypes.swift): objects built with `T.make([spreads]) { _o in ... }` */
const RIDGE_FIELDS: Record<string, Record<string, string>> = {
  RShape: {k: 'String', x: 'Double', y: 'Double', r: 'Double', p: '[Double]', m: 'String', a: 'Double?', ry: 'Double?', w: 'Double?', a0: 'Double?', a1: 'Double?', dash: 'Double?', soft: 'Bool?'},
  RCam: {s: 'Double', x: 'Double', y: 'Double', r: 'Double', px: 'Double?', py: 'Double?'},
  RScene: {
    seed: 'Double', tree: 'Double', cracks: 'Double', broken: 'Double', rubble: 'Double', sun: 'Double', night: 'Double', mist: 'Double', rain: 'Double', peak: 'Double', kind: 'String',
    rockIn: 'Double?', noRock: 'Bool?', noYou: 'Bool?', hgBg: 'String?', prop: 'String?', candle: 'Double?', moonX: 'Double?', moonY: 'Double?', boatX: 'Double?', sand: 'Double?', charge: 'Double?', stones: 'Double?', trail: 'Double?', birds: 'Double?', chipsAt: 'Double?',
    snow: 'Double?', frozen: 'Bool?', fireflies: 'Double?', drip: 'Bool?', tide: 'Double?', steps: 'Double?', beacon: 'Double?', lanterns: '[Double]?', stars: 'Double?', starLines: 'Double?', shoot: 'Double?', skips: '[Double]?', skipN: 'Double?', skipDone: 'Double?', burst: 'Double?', burstAt: 'String?', flash: 'Double?', ripples: 'Double?',
  },
};
function ridgeConfig(): Config {
  const m = matrixConfig('RW');
  const shapeKeys = ['{a,k,m,r,x,y}', '{a,a0,a1,dash,k,m,r,ry,w,x,y}', '{a,dash,k,m,p,w}', '{a,k,m,p,soft}', '{a,k,m,p,r}', '{a,k,m}'];
  const typeMap: Record<string, string> = {
    CanvasRenderingContext2D: 'C2D', HTMLCanvasElement: 'C2DSurface', CanvasGradient: 'C2DGradient', CanvasPattern: 'C2DStyle', Path2D: 'C2DPath',
    Scene: 'RScene', Scene2: 'RScene', Scene3: 'RScene', P: 'RScene', 'Partial<Scene3>': 'RScene', 'Partial<Scene2>': 'RScene', 'Partial<Scene>': 'RScene',
    Cam: 'RCam', 'Partial<Cam>': 'RCam', Shape: 'RShape',
    D4: 'MatrixLiveData', '{atgym,countdown,setupDone,stillLeft}': 'MatrixLiveData', Data11: 'RData', '{day,icon,live,sessions,week}': 'RData', PC: 'RPC',
    '{kind,t}': 'HapticCue', Hap: '[HapticCue]',
    Painter: 'RPainter', Painter2: 'RPainter2', Painter3: 'RPainter3',
  };
  for (const k of shapeKeys) typeMap[k] = 'RShape';
  const valueOf = (em: Emitter, v: any, sw: string): string => {
    const u = em.unwrapParens(v);
    if ((ts.isIdentifier(u) && u.text === 'undefined') || u.kind === ts.SyntaxKind.NullKeyword) return 'nil';
    const base = sw.replace(/\?$/, '');
    if (sw.endsWith('?') && ts.isConditionalExpression(u)) return `(${em.cond(u.condition)} ? ${valueOf(em, u.whenTrue, sw)} : ${valueOf(em, u.whenFalse, sw)})`;
    if (sw.endsWith('?') && !ts.isLiteralExpression(u) && !ts.isArrayLiteralExpression(u) && em.isOptional(em.typeOf(v))) return em.expr(v);
    return em.elemValue(v, base);
  };
  return {
    enumName: 'RW',
    ridge: true,
    typeMap,
    importMap: {PROOF: 'PROOF'},
    skip: new Set([
      // wash.ts: hand-written in RidgeRuntime.swift
      'rng', 'grain', 'grainTex', 'palette', 'P', 'mk',
      // props13.ts
      'FIX', 'fx', 'FRAME', 'frameOf', 'build', 'worldShapes',
      // stage13.ts: Matrix only
      'toTargets', 'applyCam', 'camPt', 'CELL', 'B',
    ]),
    objHook: (em, node, sw) => {
      if (sw === 'HapticCue') return m.objHook!(em, node, sw);
      const fields = RIDGE_FIELDS[sw];
      if (!fields) return undefined;
      const bases: string[] = [];
      const sets: string[] = [];
      for (const p of node.properties) {
        if (ts.isSpreadAssignment(p)) {
          if (sets.length) em.warn(p, 'spread after fields in a builder object');
          bases.push(em.expr(p.expression));
          continue;
        }
        const k = ts.isShorthandPropertyAssignment(p) ? p.name.text : propName(p.name);
        const v = ts.isShorthandPropertyAssignment(p) ? p.name : p.initializer;
        const f = fields[k];
        if (!f) {
          em.warn(p, `${sw}.${k} unknown field`);
          continue;
        }
        sets.push(`_o.${esc(k)} = ${valueOf(em, v, f)}`);
      }
      return `${sw}.make([${bases.join(', ')}]) { _o in ${sets.length ? sets.join('; ') : '_ = _o'} }`;
    },
    callHook: (em, node) => {
      const callee = node.expression;
      // FIX.has(q): the shape's own flag
      if (ts.isPropertyAccessExpression(callee) && ts.isIdentifier(callee.expression) && callee.expression.text === 'FIX' && callee.name.text === 'has') return `${em.wrap(em.expr(node.arguments[0]))}.fixed`;
      if (ts.isIdentifier(callee) && callee.text === 'fx') return `fx(${em.expr(node.arguments[0])})`;
      return undefined;
    },
  };
}

/** copies web-reference and rewrites the painter classes' members into free functions */
function ridgeSources(): string {
  const SRC = path.join(process.env.TMPDIR ?? '/tmp', 'ridge-src');
  fs.rmSync(SRC, {recursive: true, force: true});
  fs.cpSync(WEB, SRC, {recursive: true});
  const memberText = (file: string, cls: string) => {
    const text = fs.readFileSync(file, 'utf8');
    const sf = ts.createSourceFile(file, text, ts.ScriptTarget.ES2020, true);
    const c = sf.statements.find((s: any) => ts.isClassDeclaration(s) && s.name?.text === cls);
    return {text, members: c.members as any[]};
  };
  // wash2: the kinds table becomes kind_<name>(PNT, ...) plus a dispatcher
  {
    const f = path.join(SRC, 'hero10/wash2.ts');
    const {text, members} = memberText(f, 'Painter2');
    const kinds = members.find((m: any) => ts.isPropertyDeclaration(m) && m.name.text === 'kinds');
    const types = ['CanvasRenderingContext2D', 'number', 'number', 'Layout', 'Pal', 'Scene2', 'Theme', 'number', 'string'];
    const out: string[] = [];
    const names: string[] = [];
    for (const p of kinds.initializer.properties) {
      const fn = p.initializer;
      const ps = fn.parameters.map((q: any, i: number) => `${q.name.getText()}: ${types[i]}`).join(', ');
      let body = ts.isBlock(fn.body) ? fn.body.getText() : `{ ${fn.body.getText()}; }`;
      body = body.replace(/this\.kinds\[([^\]]+)\]\(/g, 'kindDispatch(PNT, $1, ').replace(/\bthis\./g, 'PNT.');
      const name = propName(p.name);
      names.push(name);
      out.push(`export function kind_${name}(PNT: Painter2, ${ps}): void ${body}`);
    }
    out.push(`export function kindDispatch(PNT: Painter2, k: string, ctx: CanvasRenderingContext2D, w: number, h: number, L: Layout, pal: Pal, S: Scene2, theme: Theme, t: number, key: string): void {\n  switch (k) {\n${names.map((n) => `    case '${n}':\n      kind_${n}(PNT, ctx, w, h, L, pal, S, theme, t, key);\n      break;`).join('\n')}\n  }\n}`);
    fs.writeFileSync(f, text + '\n// ---- generated by ts2swift ridge mode ----\n' + out.join('\n\n') + '\n');
  }
  // wash3: rnd collides with props13's rnd (k=997 there); overlay becomes overlay3(...)
  {
    const f = path.join(SRC, 'hero12/wash3.ts');
    fs.writeFileSync(f, fs.readFileSync(f, 'utf8').replace(/\brnd\b/g, 'rnd3'));
    const {text, members} = memberText(f, 'Painter3');
    const ov = members.find((m: any) => ts.isMethodDeclaration(m) && m.name.text === 'overlay');
    const ps = ov.parameters.map((q: any) => q.getText()).join(', ');
    const body = ov.body.getText().replace(/\bthis\./g, 'PNT.');
    fs.writeFileSync(f, text + `\n// ---- generated by ts2swift ridge mode ----\nexport function overlay3(${ps}): void ${body}\n`);
  }
  return SRC;
}

// The draw closure is emitted through the Emitter so it can see the function stack.
(Emitter.prototype as any).drawClosure = function (this: Emitter, dr: any): string {
  const du = this.unwrapParens(dr);
  if (ts.isIdentifier(du)) return `{ (g: inout MatrixBoard, c: MatrixContext) -> SceneOut in ${this.expr(du)}(&g, c) }`;
  const saved = this.lines, savedInd = this.ind;
  this.lines = [];
  this.ind = savedInd + 1;
  const ps = du.parameters;
  const gName = ps[0] && ts.isIdentifier(ps[0].name) ? esc(ps[0].name.text) : 'g';
  let cName = 'c';
  const pre: string[] = [];
  if (ps[1]) {
    if (ts.isIdentifier(ps[1].name)) cName = esc(ps[1].name.text);
    else {
      cName = '_c';
      pre.push(...this.destructure(ps[1].name, '_c', this.typeOf(ps[1].name), false));
    }
  }
  for (const p of pre) this.w(p);
  this.fnStack.push({kind: 'draw', ret: 'SceneOut', isDraw: true});
  if (ts.isBlock(du.body)) {
    for (const s of du.body.statements) this.stmt(s);
    const last = du.body.statements[du.body.statements.length - 1];
    if (!last || !ts.isReturnStatement(last)) this.w('return .none');
  } else {
    const bt = this.typeOf(du.body);
    if (bt.flags & (ts.TypeFlags.Void | ts.TypeFlags.Undefined)) {
      this.exprStmt(du.body);
      this.w('return .none');
    } else this.w(`return ${this.retValue(du.body, 'SceneOut')}`);
  }
  this.fnStack.pop();
  const inner = this.lines;
  this.lines = saved;
  this.ind = savedInd;
  return `{ (${gName}: inout MatrixBoard, ${cName}: MatrixContext) -> SceneOut in\n${inner.join('\n')}\n${'    '.repeat(savedInd)}}`;
};
interface Emitter {
  drawClosure(dr: any): string;
}

/** emit a module (a scene file) as `extension MX { enum Name { ... } }` */
export type Shared = {generated: Map<string, string>; genDecls: string[]; tmp: number};
export function emitModule(checker: any, sf: any, cfg: Config, header: string, outerOpen: string[], outerClose: string[], shared?: Shared): {text: string; warnings: string[]} {
  const em = new Emitter(checker, sf, cfg);
  if (shared) {
    em.generated = shared.generated;
    em.genDecls = shared.genDecls;
    em.tmp = shared.tmp;
  }
  em.analyzeMutations(sf);
  const body: string[] = [];
  em.lines = body;
  em.ind = outerOpen.length;
  em.fnStack.push({kind: 'module', ret: 'Void'});
  const stmts = sf.statements.filter((s: any) => !ts.isImportDeclaration(s) && !ts.isTypeAliasDeclaration(s) && !ts.isInterfaceDeclaration(s) && !(ts.isExpressionStatement(s) && ts.isVoidExpression(s.expression)) && !ts.isExportDeclaration(s));
  // top-level statements that are not declarations: wrap with the declarations they mutate
  const isDecl = (s: any) => ts.isVariableStatement(s) || ts.isFunctionDeclaration(s) || ts.isClassDeclaration(s);
  const loose = stmts.map((s: any, i: number) => (isDecl(s) ? -1 : i)).filter((i: number) => i >= 0);
  let blockStart = -1, blockEnd = -1;
  if (loose.length) {
    blockEnd = loose[loose.length - 1];
    // the block starts at the first declaration of a variable that a loose statement mutates
    const muts = new Set<any>();
    const sub = new Emitter(checker, sf, cfg);
    for (const i of loose) sub.analyzeMutations(stmts[i]);
    for (const s of sub.mutated) muts.add(s);
    blockStart = loose[0];
    stmts.forEach((s: any, i: number) => {
      if (i >= blockStart || !ts.isVariableStatement(s)) return;
      for (const d of s.declarationList.declarations) {
        if (ts.isIdentifier(d.name) && muts.has(checker.getSymbolAtLocation(d.name))) blockStart = Math.min(blockStart, i);
      }
    });
  }
  const initVars: {name: string; sw: string}[] = [];
  let k = 0;
  while (k < stmts.length) {
    const s = stmts[k];
    if (k === blockStart) {
      // one static closure that runs the module code in order
      const id = em.fresh('_module');
      const inner: string[] = [];
      const saved = em.lines, savedInd = em.ind;
      em.lines = inner;
      em.ind = savedInd + 1;
      const funcs: any[] = [];
      for (let j = blockStart; j <= blockEnd; j++) {
        const t = stmts[j];
        if (ts.isVariableStatement(t)) {
          const fnOnly = t.declarationList.declarations.every((d: any) => d.initializer && (ts.isArrowFunction(em.unwrapParens(d.initializer)) || ts.isFunctionExpression(em.unwrapParens(d.initializer))));
          if (fnOnly) {
            funcs.push(t);
            continue;
          }
          for (const d of t.declarationList.declarations) {
            if (ts.isIdentifier(d.name) && !(d.initializer && ts.isArrowFunction(em.unwrapParens(d.initializer)))) initVars.push({name: d.name.text, sw: em.ty(em.typeOf(d.name))});
          }
          em.varStmt(t.declarationList, false);
        } else if (ts.isFunctionDeclaration(t)) funcs.push(t);
        else em.stmt(t);
      }
      if (initVars.length === 1) em.w(`return ${esc(initVars[0].name)}`);
      else em.w(`return (${initVars.map((v) => `${v.name}: ${esc(v.name)}`).join(', ')})`);
      em.lines = saved;
      em.ind = savedInd;
      const tupleT = initVars.length === 1 ? initVars[0].sw : `(${initVars.map((v) => `${v.name}: ${v.sw}`).join(', ')})`;
      em.w(`private static let ${id}: ${tupleT} = {`);
      em.lines.push(...inner);
      em.w('}()');
      for (const v of initVars) em.w(`static var ${esc(v.name)}: ${v.sw} { ${id}${initVars.length === 1 ? '' : '.' + v.name} }`);
      for (const f of funcs) {
        if (ts.isFunctionDeclaration(f)) em.funcDecl(f.name.text, f, true);
        else em.varStmt(f.declarationList, true);
      }
      k = blockEnd + 1;
      continue;
    }
    em.topLevel(s);
    k++;
  }
  em.fnStack.pop();
  if (shared) shared.tmp = em.tmp;
  const pad = '    '.repeat(outerOpen.length);
  const gen = shared ? [] : em.genDecls.map((d) => d.split('\n').map((l) => pad + l).join('\n'));
  const text = [header, ...outerOpen.map((l, i) => '    '.repeat(i) + l), ...gen, ...body, ...outerClose.map((l, i) => '    '.repeat(outerClose.length - 1 - i) + l), ''].join('\n');
  return {text, warnings: em.warnings};
}

interface Emitter {
  topLevel(s: any): void;
}
(Emitter.prototype as any).topLevel = function (this: Emitter, s: any) {
  if (ts.isVariableStatement(s)) {
    const exported = s.modifiers?.some((m: any) => m.kind === ts.SyntaxKind.ExportKeyword);
    for (const d of s.declarationList.declarations) {
      if (ts.isIdentifier(d.name) && this.cfg.skip?.has(d.name.text)) continue;
      if (ts.isIdentifier(d.name) && d.name.text === 'SCENES' && d.initializer && ts.isArrayLiteralExpression(this.unwrapParens(d.initializer))) {
        const names: string[] = [];
        this.unwrapParens(d.initializer).elements.forEach((el: any, i: number) => {
          const u = this.unwrapParens(el);
          if (ts.isIdentifier(u)) names.push(esc(u.text));
          else {
            const nm = `scene${i}`;
            names.push(nm);
            this.w(`static let ${nm}: MatrixScene = ${this.objLit(u, 'MatrixScene')}`);
          }
        });
        this.w(`public static let SCENES: [MatrixScene] = [${names.join(', ')}]`);
        continue;
      }
      const single = {...s.declarationList, declarations: [d]};
      void exported;
      this.varStmt(single, true);
    }
    return;
  }
  if (ts.isFunctionDeclaration(s)) {
    this.funcDecl(s.name.text, s, true);
    return;
  }
  if (ts.isClassDeclaration(s)) {
    if (this.cfg.ridge) return; // painters' classes are hand-written (RidgePainter.swift)
    this.warn(s, 'class at top level (not supported in matrix mode)');
    return;
  }
  this.warn(s, `top-level ${ts.SyntaxKind[s.kind]}`);
};

// ------------------------------------------------------------------ main
async function main() {
  const mode = process.argv[2];
  const outDir = process.argv[3];
  if (mode === 'matrix') {
    const dir = path.join(WEB, 'hero13/mx');
    const files = fs.readdirSync(dir).filter((f) => f.endsWith('.ts') && f !== 'common.ts').map((f) => path.join(dir, f));
    const {checker, program} = makeProgram(files);
    let allWarn: string[] = [];
    for (const f of files) {
      const sf = program.getSourceFile(f);
      const base = path.basename(f, '.ts');
      const enumName = capital(base);
      const cfg = matrixConfig(enumName);
      const header = `//\n//  MX${enumName}.swift\n//  GymLock · Matrix hero\n//\n//  GENERATED by docs/hero-pack/swift/tools/ts2swift.ts from web-reference/hero13/mx/${base}.ts.\n//  Do not edit by hand: fix the transpiler or the source and regenerate.\n//\n\nimport Foundation\n`;
      const {text, warnings} = emitModule(checker, sf, cfg, header, ['extension MX {', `public enum ${enumName} {`], ['}', '}']);
      fs.writeFileSync(path.join(outDir, `MX${enumName}.swift`), text);
      allWarn = allWarn.concat(warnings);
    }
    for (const w of allWarn) console.error('warn:', w);
    console.error(`${files.length} files, ${allWarn.length} warnings`);
  }
  if (mode === 'ridge') {
    const SRC = ridgeSources();
    const rel = ['hero10/wash.ts', 'hero10/wash2.ts', 'hero12/wash3.ts', 'hero13/stage13.ts', 'hero13/props13.ts'];
    const files = rel.map((r) => path.join(SRC, r));
    const {checker, program} = makeProgram(files);
    const cfg = ridgeConfig();
    const shared: Shared = {generated: new Map(), genDecls: [], tmp: 0};
    let allWarn: string[] = [];
    // top-level names share one namespace (extension RW): report collisions
    const seen = new Map<string, string>();
    for (const f of files) {
      const sf = program.getSourceFile(f);
      for (const s of sf.statements) {
        const names: string[] = [];
        if (ts.isVariableStatement(s)) for (const d of s.declarationList.declarations) if (ts.isIdentifier(d.name)) names.push(d.name.text);
        if (ts.isFunctionDeclaration(s) && s.name) names.push(s.name.text);
        for (const n of names) {
          if (cfg.skip!.has(n)) continue;
          if (seen.has(n)) allWarn.push(`duplicate top-level ${n} in ${path.basename(f)} and ${seen.get(n)}`);
          seen.set(n, path.basename(f));
        }
      }
    }
    for (const f of files) {
      const sf = program.getSourceFile(f);
      const base = path.basename(f, '.ts');
      const name = `RW${capital(base)}`;
      const header = `//\n//  ${name}.swift\n//  GymLock · Ridge hero\n//\n//  GENERATED by docs/hero-pack/swift/tools/ts2swift.ts (ridge mode) from web-reference/${rel[files.indexOf(f)]}.\n//  Do not edit by hand: fix the transpiler or the source and regenerate.\n//\n\nimport Foundation\nimport CoreGraphics\n`;
      const {text, warnings} = emitModule(checker, sf, cfg, header, ['nonisolated extension RW {'], ['}'], shared);
      fs.writeFileSync(path.join(outDir, `${name}.swift`), text);
      allWarn = allWarn.concat(warnings);
    }
    const typesHeader = `//\n//  RWTypes.swift\n//  GymLock · Ridge hero\n//\n//  GENERATED by docs/hero-pack/swift/tools/ts2swift.ts (ridge mode): the object types the painters share.\n//  Do not edit by hand.\n//\n\nimport Foundation\n\n`;
    fs.writeFileSync(path.join(outDir, 'RWTypes.swift'), typesHeader + shared.genDecls.join('\n\n') + '\n');
    for (const w of allWarn) console.error('warn:', w);
    console.error(`ridge: ${files.length} files, ${allWarn.length} warnings`);
  }
  if (mode === 'story') {
    // hero13/mxstory.ts: every done-flow screen. The dispatcher (mxStory, VERIFIED, FINISH) is
    // hand-written in MatrixStoryView.swift so the board stays an inout value.
    const f = path.join(WEB, 'hero13/mxstory.ts');
    const {checker, program} = makeProgram([f]);
    const sf = program.getSourceFile(f);
    const cfg = matrixConfig('Story');
    cfg.importMap = {...cfg.importMap, hash: 'MatrixSinHash.hash'};
    cfg.typeMap = {...cfg.typeMap, SC: 'MXStoryContext', MCal: 'MXStoryCal', Glow: 'MatrixGlow', '{done,today}': 'MXStoryWeek', '{day,sessions}': 'MXStoryDay', Res: 'MXStoryRes', '{flash,glow,o,ph}': 'MXStoryRes'};
    cfg.skip = new Set(['mxStory', 'VERIFIED', 'FINISH', 'MX_CLIMAX', 'MX_TALLY']);
    const header = `//\n//  MXStory.swift\n//  GymLock · Matrix hero\n//\n//  GENERATED by docs/hero-pack/swift/tools/ts2swift.ts from web-reference/hero13/mxstory.ts.\n//  Do not edit by hand: fix the transpiler or the source and regenerate.\n//\n\nimport Foundation\n`;
    const {text, warnings} = emitModule(checker, sf, cfg, header, ['extension MX {', 'public enum Story {'], ['}', '}']);
    fs.writeFileSync(path.join(outDir, 'MXStory.swift'), text);
    for (const w of warnings) console.error('warn:', w);
    console.error(`story: ${warnings.length} warnings`);
  }
}
if (import.meta.main) await main();
