/**
 * Browser half of dsh-sidebar-layout-fix.
 *
 * Why this exists
 * ---------------
 * `sidebar.footer.action` is a *list* slot: every plugin that registers an id
 * there gets its own cell. Its container is `._2H3hWW_footerActions`, rendered
 * as a plain row (`display:flex`). The shipped Settings row is built for a
 * single full-width item, and plugin authors copy that geometry, so two
 * entries that both ask for `width:100%` fight over one row: the first has
 * `flex:none` and keeps the whole width, the second is squeezed to zero width
 * and its contents paint on top of the first.
 *
 * The fix stacks the cells in a column, which is what the surrounding footer
 * already looks like, and keeps the collapsed (56px rail) case as centred
 * round buttons.
 *
 * Scope
 * -----
 * `_footArea` is a CSS-module hash that appears exactly once in the shipped
 * client CSS (the sidebar). The composer has its own unrelated
 * `_footerActions` hash, so scoping through `_footArea` keeps this from
 * touching anything outside the sidebar footer.
 */

window.__ModuleLoader__.load({
  id: 'dsh-sidebar-layout-fix',
  factory: (require) => {
    var module = { exports: {} }
    var exports = module.exports

    var STYLE_ID = 'dsh-sidebar-layout-fix'

    var CSS = [
      // Footer action cells become rows instead of competing for one line.
      '[class*="_footArea"] [class*="_footerActions"]{',
      'display:flex!important;',
      'flex-direction:column!important;',
      'align-items:stretch!important;',
      'gap:2px!important;',
      'width:100%!important}',
      // Each cell owns a full row and may shrink instead of overflowing.
      '[class*="_footArea"] [class*="_footerActions"]>*{',
      'flex:0 0 auto!important;',
      'width:100%!important;',
      'min-width:0!important;',
      'max-width:100%!important;',
      'box-sizing:border-box!important;',
      'margin:0!important}',
      // Collapsed rail: two 36px round buttons, centred, still stacked.
      '[class*="_collapsed"] [class*="_footArea"] [class*="_footerActions"]{',
      'align-items:center!important}',
      '[class*="_collapsed"] [class*="_footArea"] [class*="_footerActions"]>*{',
      'width:36px!important;max-width:36px!important}',
    ].join('')

    function apply() {
      if (typeof document === 'undefined') return
      if (document.getElementById(STYLE_ID)) return
      var el = document.createElement('style')
      el.id = STYLE_ID
      el.textContent = CSS
      ;(document.head || document.documentElement).appendChild(el)
    }

    exports.name = 'sidebar-layout-fix'
    exports.apply = apply
    exports.inject = []

    return module.exports
  },
})
