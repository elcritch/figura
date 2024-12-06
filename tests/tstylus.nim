## This is a simple example on how to use Stylus' tokenizer.
import figuro/ui/basiccss
import chroma

import std/unittest

suite "css parser":

  test "blocks":
    # skip()
    const src = """

    Button {
    }

    Button.btnBody {
    }

    Button child {
    }

    Button < directChild {
    }

    Button < directChild.field {
    }

    """

    let parser = newCssParser(src)
    let res = parse(parser)
    check res[0].selectors == @[CssSelector(cssType: "Button")]
    check res[1].selectors == @[CssSelector(cssType: "Button", class: "btnBody")]
    # echo "results: ", res[2].selectors.repr
    check res[2].selectors == @[
      CssSelector(cssType: "Button", combinator: skNone),
      CssSelector(cssType: "child", combinator: skDescendent)
    ]

  test "properties":
    const src = """

    Button {
      color-background: #00a400;
      color: rgb(214, 122, 127);
      border-width: 1;
    }

    """

    let parser = newCssParser(src)
    let res = parse(parser)[0]
    check res.selectors == @[CssSelector(cssType: "Button", combinator: skNone)]
    check res.properties.len() == 3
    check res.properties[0] == CssProperty(name: "color-background", value: CssColor(parseHtmlColor("#00a400")))
    check res.properties[1] == CssProperty(name: "color", value: CssColor(parseHtmlColor("rgb(214, 122, 127)")))
    # echo "\nresults:"
    # for r in res.properties:
    #   echo "\t", r.repr
    check res.properties[2] == CssProperty(name: "border-width", value: CssSize(csFixed(1.0.UiScalar)))


  test "missing property value":
    const src = """

    Button {
      color-background: ;
      color: rgb(214, 122, 127);
    }

    """

    let parser = newCssParser(src)
    let res = parse(parser)[0]
    # echo "results: ", res.repr
    check res.selectors == @[CssSelector(cssType: "Button", combinator: skNone)]
    check res.properties[0] == CssProperty(name: "color", value: CssColor(parseHtmlColor("rgb(214, 122, 127)")))

  test "missing property name":
    const src = """

    Button {
      : #00a400;
      color: rgb(214, 122, 127);
    }

    """

    let parser = newCssParser(src)
    let res = parse(parser)[0]
    # echo "results: ", res.repr
    check res.selectors == @[CssSelector(cssType: "Button", combinator: skNone)]
    check res.properties[0] == CssProperty(name: "color", value: CssColor(parseHtmlColor("rgb(214, 122, 127)")))

  test "test child descent tokenizer is working":
    skip()
    if false:
      const src = """
      Button > directChild {
      }

      Button > directChild.field {
      }
      """

      echo "trying to parse `>`..."
      let parser = newCssParser(src)
      let res = parse(parser)
      echo "results: ", res.repr
