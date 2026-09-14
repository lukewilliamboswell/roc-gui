# frozen_string_literal: true

require "rouge"

# Loaded by the documentation container so Roc examples are highlighted by the
# same server-side renderer as every other source block. Keep this lexer close
# to tree-sitter-roc's grammar and highlights query.
module Rouge
  module Lexers
    class Roc < RegexLexer
      title "Roc"
      desc "The Roc programming language"
      tag "roc"
      filenames "*.roc"

      BUILTIN_TYPES = %w[
        Bool Box Dec Decode Dict Encode F32 F64 Hash I8 I16 I32 I64 I128
        Inspect Int List Num Result Set Str U8 U16 U32 U64 U128
      ].freeze

      state :root do
        rule %r/##.*$/, Comment::Special
        rule %r/#.*$/, Comment::Single

        # Roc multiline strings consist of source lines introduced by two
        # backslashes. Treat every line independently so normal lexing resumes
        # even when a documentation excerpt is incomplete.
        rule %r/^\\\\/, Str::Double, :multiline_string
        rule %r/"/, Str::Double, :string
        rule %r/'(?:\\(?:[\\"'ntbrafv]|u\([0-9A-Fa-f]{1,8}\))|[^\n\t\r'\\])'/,
             Str::Char

        rule %r/\b(?:app|as|break|crash|else|expect|exposing|for|hosted|if|import|in|match|module|package|packages|platform|provides|requires|return|targets|to|var|where|while)\b/,
             Keyword
        rule %r/\b(?:and|or)\b/, Operator::Word
        rule %r/\bdbg\b/, Name::Builtin
        rule %r/\b(?:true|false)\b/, Keyword::Constant

        rule %r/\b(?:#{BUILTIN_TYPES.join('|')})\b/, Keyword::Type

        # Numeric type suffixes are immediate `.UpperType` suffixes. Put these
        # before ordinary floats and integers so the complete literal is one
        # token. Separators are accepted in every integer form.
        rule %r/\b(?:0[xX][0-9A-Fa-f](?:_?[0-9A-Fa-f])*|0[oO][0-7](?:_?[0-7])*|0[bB][01](?:_?[01])*|\d(?:_?\d)*(?:\.\d(?:_?\d)*)?(?:[eE][+-]?\d(?:_?\d)*)?)\.[A-Z][A-Za-z0-9_]*\b/,
             Num
        rule %r/\b\d(?:_?\d)*\.\d(?:_?\d)*(?:[eE][+-]?\d(?:_?\d)*)?(?:f32|f64)?\b/,
             Num::Float
        rule %r/\b\d(?:_?\d)*[eE][+-]?\d(?:_?\d)*(?:f32|f64)?\b/, Num::Float
        rule %r/\b0[xX][0-9A-Fa-f](?:_?[0-9A-Fa-f])*\b/, Num::Hex
        rule %r/\b0[oO][0-7](?:_?[0-7])*\b/, Num::Oct
        rule %r/\b0[bB][01](?:_?[01])*\b/, Num::Bin
        rule %r/\b\d(?:_?\d)*\b/, Num::Integer

        # Effectful (`name!`), shadowable (`_name`), and mutable (`$name`)
        # identifiers are all part of Roc's identifier grammar.
        rule %r/(\.)(\$?_*\p{Ll}[\p{XID_Continue}]*!?)(?=\s*\()/u do
          groups(Punctuation, Name::Function)
        end
        rule %r/(\.)(\$?_*\p{Ll}[\p{XID_Continue}]*!?)/u do
          groups(Punctuation, Name::Attribute)
        end
        rule %r/\$?_*\p{Ll}[\p{XID_Continue}]*!?(?=\s*\()/u, Name::Function
        rule %r/\b[A-Z][\p{XID_Continue}]*(?=\.)/u, Name::Namespace
        rule %r/\$?_*\p{Ll}[\p{XID_Continue}]*!?/u, Name
        rule %r/\b[A-Z][\p{XID_Continue}]*/u, Name::Class
        rule %r/_\b/, Name::Builtin

        rule %r/\.\.\.|\.\.<|\.\.=|\|>|=>|->|==|!=|<=|>=|&&|\|\||\/\/|\?\?|[+*\-\/%<>=^&|!?]/,
             Operator
        rule %r/::|:=|\?:|\.\.|[{}\[\](),.:\\]/, Punctuation
        rule %r/\s+/, Text::Whitespace
      end

      state :string do
        rule %r/"/, Str::Double, :pop!
        rule %r/\\(?:[\\"'ntbrafv]|u\([0-9A-Fa-f]{1,8}\))/, Str::Escape
        rule %r/\$\{/, Str::Interpol, :interpolation
        rule %r/[^\\"$]+|\$(?!\{)|\\/, Str::Double
      end

      state :multiline_string do
        rule %r/\r?\n/, Text::Whitespace, :pop!
        rule %r/\\(?:[\\"'ntbrafv]|u\([0-9A-Fa-f]{1,8}\))/, Str::Escape
        rule %r/\$\{/, Str::Interpol, :interpolation
        rule %r/[^\\$\r\n]+|\$(?!\{)|\\/, Str::Double
      end

      # Balance record/block braces inside interpolation rather than ending at
      # the first `}`. All ordinary expression rules remain available here.
      state :interpolation do
        rule %r/\{/, Punctuation, :interpolation
        rule %r/\}/, Str::Interpol, :pop!
        mixin :root
      end
    end
  end
end
