callWithJQuery = (pivotModule) ->
    if typeof exports is "object" and typeof module is "object" # CommonJS
        pivotModule require("jquery")
    else if typeof define is "function" and define.amd # AMD
        define ["jquery"], pivotModule
    # Plain browser env
    else
        pivotModule jQuery

callWithJQuery ($) ->

    class SubtotalPivotData extends $.pivotUtilities.PivotData
        constructor: (input, opts) ->
            super input, opts

        processKey = (record, totals, keys, attrs, getAggregator) ->
            key = []
            addKey = false
            for attr in attrs
                key.push record[attr] ? "null"
                flatKey = key.join String.fromCharCode(0)
                if not totals[flatKey]
                    totals[flatKey] = getAggregator key.slice()
                    addKey = true
                totals[flatKey].push record
            keys.push key if addKey
            return key

        processRecord: (record) -> #this code is called in a tight loop
            rowKey = []
            colKey = []

            @allTotal.push record
            rowKey = processKey record, @rowTotals, @rowKeys, @rowAttrs, (key) =>
                return @aggregator this, key, []
            colKey = processKey record, @colTotals, @colKeys, @colAttrs, (key) =>
                return @aggregator this, [], key
            m = rowKey.length-1
            n = colKey.length-1
            return if m < 0 or n < 0
            for i in [0..m]
                fRowKey = rowKey.slice(0, i+1)
                flatRowKey = fRowKey.join String.fromCharCode(0)
                @tree[flatRowKey] = {} if not @tree[flatRowKey]
                for j in [0..n]
                    fColKey = colKey.slice 0, j+1
                    flatColKey = fColKey.join String.fromCharCode(0)
                    @tree[flatRowKey][flatColKey] = @aggregator this, fRowKey, fColKey if not @tree[flatRowKey][flatColKey]
                    @tree[flatRowKey][flatColKey].push record

    $.pivotUtilities.SubtotalPivotData = SubtotalPivotData

    SubtotalRenderer = (pivotData, opts) ->
        defaults =
            table: clickCallback: null
            localeStrings: totals: "Totals"

        opts = $.extend true, {}, defaults, opts

        arrowCollapsed = opts.arrowCollapsed ?= "\u25B6"
        arrowExpanded = opts.arrowExpanded ?= "\u25E2"
        classExpanded = "expanded"
        classCollapsed = "collapsed"
        colAttrs = pivotData.colAttrs
        rowAttrs = pivotData.rowAttrs
        rowKeys = pivotData.getRowKeys()
        colKeys = pivotData.getColKeys()
        tree = pivotData.tree
        rowTotals = pivotData.rowTotals
        colTotals = pivotData.colTotals
        allTotal = pivotData.allTotal

        # Based on http://stackoverflow.com/questions/195951/change-an-elements-class-with-javascript -- Begin
        hasClass = (element, className) ->
            regExp = new RegExp "(?:^|\\s)" + className + "(?!\\S)", "g"
            element.className.match regExp

        removeClass = (element, className) ->
            regExp = new RegExp "(?:^|\\s)" + className + "(?!\\S)", "g"
            element.className = element.className.replace regExp, ''

        addClass = (element, className) ->
            element.className += (" " + className) if not hasClass element, className

        replaceClass = (element, replaceClassName, byClassName) ->
            removeClass element, replaceClassName
            addClass element, byClassName
        # Based on http://stackoverflow.com/questions/195951/change-an-elements-class-with-javascript -- End

        getTableEventHandlers = (value, rowValues, colValues) ->
            return if not opts.table and not opts.table.eventHandlers
            eventHandlers = {}
            for own event, handler of opts.table.eventHandlers
                filters = {}
                filters[attr] = colValues[i] for own i, attr of colAttrs when colValues[i]?
                filters[attr] = rowValues[i] for own i, attr of rowAttrs when rowValues[i]?
                eventHandlers[event] = (e) -> handler(e, value, filters, pivotData)
            return eventHandlers

        createCell = (cellType, className, textContent, attributes, eventHandlers) ->
            th = document.createElement cellType
            th.className = className if className?
            th.textContent = textContent if textContent?
            th.setAttribute attr, val for own attr, val of attributes if attributes?
            th.addEventListener event, handler for own event, handler of eventHandlers if eventHandlers?
            return th

        processKeys = (keysArr, className) ->
            headers = []
            lastRow = keysArr.length - 1
            lastCol = keysArr[0].length - 1
            rMark = []
            th = createCell "th", className, keysArr[0][0]
            key = []
            key.push keysArr[0][0]
            nodePos = 0
            node = {
                node: nodePos,
                row: 0,
                col: 0,
                th: th,
                parent: null,
                children: [],
                descendants: lastCol,
                leaves: 1,
                key: key,
                flatKey: key.join String.fromCharCode(0)}
            headers.push node
            rMark[0] = node
            c = 1
            while c <= lastCol
                th = createCell "th", className, keysArr[0][c]
                key = key.slice()
                key.push keysArr[0][c]
                ++nodePos
                node =  {
                    node: nodePos,
                    row: 0,
                    col: c,
                    th: th,
                    parent: rMark[c-1],
                    children: [],
                    descendants: lastCol-c,
                    leaves: 1,
                    key: key,
                    flatKey: key.join String.fromCharCode(0)}
                rMark[c] = node
                rMark[c-1].children.push node
                ++c
            rMark[lastCol].leaves = 0
            r = 1
            while r <= lastRow
                repeats = true
                key = []
                c = 0
                while c <= lastCol
                    key = key.slice()
                    key.push keysArr[r][c]
                    if ((keysArr[r][c] is keysArr[rMark[c].row][c]) and (c isnt lastCol)  and (repeats))
                        repeats = true
                        ++c
                        continue
                    th = createCell "th", className, keysArr[r][c]
                    ++nodePos
                    node = {
                        node: nodePos,
                        row: r,
                        col: c,
                        th: th,
                        parent: null,
                        children: [],
                        descendants: 0,
                        leaves: 1,
                        key: key,
                        flatKey: key.join String.fromCharCode(0)}
                    if c is 0
                        headers.push node
                    else
                        node.parent = rMark[c-1]
                        rMark[c-1].children.push node
                        x = 0
                        while x <= c-1
                            ++rMark[x].descendants
                            ++x
                    rMark[c] = node
                    repeats = false
                    ++c
                ++rMark[c].leaves for c in [0..lastCol]
                rMark[lastCol].leaves = 0
                ++r
            return headers

        buildColHeaderHeader = (thead, colHeaderHeaders, rowAttrs, colAttrs, tr, col) ->
            colAttr = colAttrs[col]
            textContent = colAttr
            className = "pvtAxisLabel"
            if col < colAttrs.length-1
                className += " expanded"
                textContent = " " + arrowExpanded + " " + colAttr
            th = createCell "th", className, textContent
            th.setAttribute "data-colAttr", colAttr
            tr.appendChild th
            colHeaderHeaders.push {
                tr: tr,
                th: th,
                clickStatus: classExpanded,
                expandedCount: 0,
                nHeaders: 0}
            thead.appendChild tr

        buildColHeaderHeaders = (thead, colHeaderHeaders, rowAttrs, colAttrs) ->
            tr = document.createElement "tr"
            if rowAttrs.length != 0
                tr.appendChild createCell "th", null, null, {
                    colspan: rowAttrs.length,
                    rowspan: colAttrs.length}
            buildColHeaderHeader thead, colHeaderHeaders, rowAttrs, colAttrs, tr, 0
            for c in [1..colAttrs.length] when c < colAttrs.length
                tr = document.createElement("tr")
                buildColHeaderHeader thead, colHeaderHeaders, rowAttrs, colAttrs, tr, c

        buildColHeaderHeadersClickEvents = (colHeaderHeaders, colHeaderCols, colAttrs) ->
            n = colAttrs.length-1
            for i in [0..n] when i < n
                th = colHeaderHeaders[i].th
                colAttr = colAttrs[i]
                th.onclick = (event) ->
                    event = event || window.event
                    toggleColHeaderHeader colHeaderHeaders, colHeaderCols, colAttrs, event.target.getAttribute "data-colAttr"

        buildColHeaders = (colHeaderHeaders, colHeaderCols, colHeader, rowAttrs, colAttrs) ->
            # DF Recurse
            for h in colHeader.children
                buildColHeaders colHeaderHeaders, colHeaderCols, h, rowAttrs, colAttrs
            # Process
            hh = colHeaderHeaders[colHeader.col]
            ++hh.expandedCount
            ++hh.nHeaders
            tr = hh.tr
            th = colHeader.th
            th.setAttribute "data-colHeader", th.textContent
            th.setAttribute("rowspan", 2) if colHeader.col == colAttrs.length-1 and rowAttrs.length != 0
            th.setAttribute("colspan", colHeader.descendants+1) if colHeader.children.length !=0
            th.setAttribute("data-node", colHeaderCols.length)
            tr.appendChild(th)
            if colHeader.children.length != 0
                addClass th, classExpanded
                th.textContent = " " + arrowExpanded + " " + th.textContent
                th.onclick = (event) ->
                    event = event || window.event
                    toggleCol colHeaderHeaders, colHeaderCols, parseInt event.target.getAttribute "data-node"
                rowspan = colAttrs.length-(colHeader.col+1) + if rowAttrs.length != 0 then 1 else 0
                style = "pvtColLabel pvtColSubtotal col" + colHeader.row
                th = createCell "th", style, '', {"rowspan": rowspan}
                colHeader.children[0].tr.appendChild th
                colHeader.sTh = th
            colHeader.clickStatus = classExpanded
            colHeader.tr = tr
            colHeaderCols.push colHeader

        buildRowHeaderHeaders = (thead, rowHeaderHeaders, rowAttrs, colAttrs) ->
            tr = document.createElement "tr"
            rowHeaderHeaders.hh = []
            for own i, rowAttr of rowAttrs
                textContent = rowAttr
                className = "pvtAxisLabel"
                if i < rowAttrs.length-1
                    className += " expanded"
                    textContent = " " + arrowExpanded + " " + rowAttr
                th = createCell "th", className, textContent
                th.setAttribute "data-rowAttr", rowAttr
                tr.appendChild th
                rowHeaderHeaders.hh.push {
                    th: th,
                    clickStatus: classExpanded,
                    expandedCount: 0,
                    nHeaders: 0}
            if colAttrs.length != 0
                th = createCell "th"
                tr.appendChild th
            thead.appendChild tr
            rowHeaderHeaders.tr = tr

        buildRowHeaderHeadersClickEvents = (rowHeaderHeaders, rowHeaderRows, rowAttrs) ->
            n = rowAttrs.length-1
            for i in [0..n] when i < n
                th = rowHeaderHeaders.hh[i]
                rowAttr = rowAttrs[i]
                th.th.onclick = (event) ->
                    event = event || window.event
                    toggleRowHeaderHeader rowHeaderHeaders, rowHeaderRows, rowAttrs, event.target.getAttribute "data-rowAttr"

        buildRowTotalsHeader = (tr, rowAttrs, colAttrs) ->
            rowspan = 1
            if colAttrs.length != 0
                rowspan = colAttrs.length + (if rowAttrs.length == 0 then 0 else 1)
            th = createCell "th", "pvtTotalLabel rowTotal", opts.localeStrings.totals, {rowspan: rowspan}
            tr.appendChild th

        buildRowHeaders = (tbody, rowHeaderHeaders, rowHeaderRows, rowHeader, rowAttrs, colAttrs) ->
            hh = rowHeaderHeaders.hh[rowHeader.col]
            ++hh.expandedCount
            ++hh.nHeaders
            tr = document.createElement "tr"
            th = rowHeader.th
            th.setAttribute "rowspan", rowHeader.descendants+1
            th.setAttribute "data-rowHeader", th.textContent
            if rowHeader.col == rowAttrs.length-1 and colAttrs.length != 0
                th.setAttribute "colspan", 2
            th.setAttribute "data-node", rowHeaderRows.length
            tr.appendChild th
            if rowHeader.children.length != 0
                addClass th, classExpanded
                th.textContent = " " + arrowExpanded + " " + th.textContent
                th.onclick = (event) ->
                    event = event || window.event
                    toggleRow rowHeaderHeaders, rowHeaderRows, parseInt event.target.getAttribute "data-node"
                colspan = rowAttrs.length-(rowHeader.col+1) + if colAttrs.length != 0 then 1 else 0
                th = createCell "th", "pvtRowLabel pvtRowSubtotal", '', {colspan: colspan}
                tr.appendChild th
            rowHeader.clickStatus = classExpanded
            rowHeader.tr = tr
            rowHeaderRows.push rowHeader
            tbody.appendChild tr
            for h in rowHeader.children
                buildRowHeaders tbody, rowHeaderHeaders, rowHeaderRows, h, rowAttrs, colAttrs

        buildValues = (rowHeaderRows, colHeaderCols) ->
            for rowHeader in rowHeaderRows
                tr = rowHeader.tr
                flatRowKey = rowHeader.flatKey
                for colHeader in colHeaderCols
                    flatColKey = colHeader.flatKey
                    aggregator = tree[flatRowKey][flatColKey] ? {value: (-> null), format: -> ""}
                    val = aggregator.value()
                    style = "pvtVal"
                    style += " pvtColSubtotal" if colHeader.children.length != 0
                    style += " pvtRowSubtotal" if rowHeader.children.length != 0
                    style += " row" + rowHeader.row +
                        " col" + colHeader.row +
                        " rowcol" + rowHeader.col +
                        " colcol" + colHeader.col
                    eventHandlers = getTableEventHandlers val, rowHeader.key, colHeader.key
                    td = createCell "td", style, aggregator.format(val), {"data-value": val}, eventHandlers
                    tr.appendChild td
                # buildRowTotal
                totalAggregator = rowTotals[flatRowKey]
                val = totalAggregator.value()
                style = "pvtTotal rowTotal"
                style += " pvtRowSubtotal" if rowHeader.children.length != 0
                style += " row" + rowHeader.row + " rowcol" + rowHeader.col
                td = createCell "td", style, totalAggregator.format(val), {
                    "data-value": val,
                    "data-row": "row"+rowHeader.row,
                    "data-col": "col"+rowHeader.col}, getTableEventHandlers val, rowHeader.key, []
                tr.appendChild td

        buildColTotalsHeader = (rowAttrs, colAttrs) ->
            tr = document.createElement "tr"
            colspan = rowAttrs.length + (if colAttrs.length == 0 then 0 else 1)
            th = createCell "th", "pvtTotalLabel colTotal", opts.localeStrings.totals, {colspan: colspan}
            tr.appendChild th
            return tr

        buildColTotals = (tr, colHeaderCols) ->
            for h in colHeaderCols
                totalAggregator = colTotals[h.flatKey]
                val = totalAggregator.value()
                style = "pvtVal pvtTotal colTotal"
                style += " pvtColSubtotal" if h.children.length != 0
                style += " col" + h.row + " colcol" + h.col
                td = createCell "td", style, totalAggregator.format(val),
                    {"data-value": val, "data-for": "col" + h.col},
                    getTableEventHandlers val, [], h.key
                tr.appendChild td

        buildGrandTotal = (result, tr) ->
            totalAggregator = allTotal
            val = totalAggregator.value()
            td = createCell "td", "pvtGrandTotal", totalAggregator.format(val),
                {"data-value": val},
                getTableEventHandlers val, [], []
            tr.appendChild td
            result.appendChild tr

        setColVisibility = (visibility, h) ->
            h.th.style.display = visibility
            if h.children.length != 0
                $(h.th).closest 'table.pvtTable'
                    .find 'tbody tr td.pvtColSubtotal.col' + h.row + '.colcol' + h.col
                    .css 'display', visibility
            else
                $(h.th)
                    .closest 'table.pvtTable'
                    .find 'tbody tr td.pvtVal.col' + h.row
                    .not '.pvtColSubtotal'
                    .css 'display', visibility
            h.sTh.style.display = visibility if h.sTh

        collapseCol = (colHeaderHeaders, colHeaderCols, c) ->
            return if not colHeaderCols[c]

            h = colHeaderCols[c]
            return if h.clickStatus is classCollapsed

            colspan = 0
            for i in [1..h.descendants] when h.descendants != 0
                d = colHeaderCols[c-i]
                if d.th.style.display isnt "none"
                    ++colspan
                    setColVisibility "none", d
            p = h.parent
            while p isnt null
                p.th.setAttribute("colspan", parseInt(p.th.getAttribute("colspan")) - colspan)
                p = p.parent
            if h.descendants != 0
                replaceClass h.th, classExpanded, classCollapsed
                h.th.textContent = " " + arrowCollapsed + " " + h.th.getAttribute "data-colHeader"
            h.clickStatus = classCollapsed
            h.th.setAttribute "colspan", 1
            h.th.style.display = ""
            colHeaderHeader = colHeaderHeaders[h.col]
            colHeaderHeader.expandedCount--
            if colHeaderHeader.expandedCount == 0
                for i in [h.col..colHeaderHeaders.length-2]
                    colHeaderHeader = colHeaderHeaders[i]
                    replaceClass colHeaderHeader.th, classExpanded, classCollapsed
                    colHeaderHeader.th.textContent = " " + arrowCollapsed + " " + colHeaderHeader.th.getAttribute "data-colAttr"
                    colHeaderHeader.clickStatus = classCollapsed

        expandChildCol = (ch) ->
            setColVisibility "", ch if ch.th.style.display is "none"
            expandChildCol gch for gch in ch.children if ch.clickStatus isnt classCollapsed

        expandCol = (colHeaderHeaders, colHeaderCols, c) ->
            return if not colHeaderCols[c]

            h = colHeaderCols[c]
            return if h.clickStatus is classExpanded

            colspan = 0
            for ch in h.children
                colspan += ch.th.colSpan
                setColVisibility "", ch if ch.th.style.display is "none"
                expandChildCol ch
            if h.descendants != 0
                replaceClass h.th, classCollapsed, classExpanded
                h.th.textContent = " " + arrowExpanded + " " + h.th.getAttribute "data-colHeader"
            h.th.setAttribute "colspan", colspan+1
            h.clickStatus = classExpanded
            h.th.style.display = ""
            h.sTh.style.display = "" if h.sTh?
            p = h.parent
            while p isnt null
                p.th.setAttribute "colspan", colspan + parseInt p.th.getAttribute "colspan"
                p = p.parent
            hh = colHeaderHeaders[h.col]
            ++hh.expandedCount
            if hh.expandedCount is hh.nHeaders
                replaceClass hh.th, classCollapsed, classExpanded
                hh.th.textContent = " " + arrowExpanded + " " + hh.th.getAttribute "data-colAttr"
                hh.clickStatus = classExpanded

        collapseRow = (rowHeaderHeaders, rowHeaderRows, r) ->
            return if not rowHeaderRows[r]

            h = rowHeaderRows[r]
            return if h.clickStatus is classCollapsed

            rowspan = 0
            for i in [1..h.descendants] when h.descendants != 0
                d = rowHeaderRows[r+i]
                if d.tr.style.display isnt "none"
                    ++rowspan
                    d.tr.style.display = "none"
            p = h.parent
            while p isnt null
                p.th.setAttribute "rowspan", parseInt p.th.getAttribute("rowspan")-rowspan
                p = p.parent
            if h.descendants != 0
                replaceClass h.th, classExpanded, classCollapsed
                h.th.textContent = " " + arrowCollapsed + " " + h.th.getAttribute "data-rowHeader"
            h.clickStatus = classCollapsed
            h.th.setAttribute "rowspan", 1
            h.tr.style.display = ""
            rowHeaderHeader = rowHeaderHeaders.hh[h.col]
            rowHeaderHeader.expandedCount--
            return if rowHeaderHeader.expandedCount != 0
            for j in [h.col..rowHeaderHeaders.hh.length-2]
                rowHeaderHeader = rowHeaderHeaders.hh[j]
                replaceClass rowHeaderHeader.th, classExpanded, classCollapsed
                rowHeaderHeader.th.textContent =
                    " " + arrowCollapsed + " " + rowHeaderHeader.th.getAttribute "data-rowAttr"
                rowHeaderHeader.clickStatus = classCollapsed

        expandChildRow = (ch) ->
            ch.tr.style.display = "" if ch.tr.style.display is "none"
            expandChildRow gch for gch in ch.children if ch.clickStatus isnt classCollapsed

        expandRow = (rowHeaderHeaders, rowHeaderRows, r) ->
            return if not rowHeaderRows[r]

            h = rowHeaderRows[r]
            return if h.clickStatus is classExpanded

            rowspan = 0
            for ch in h.children
                rowspan += ch.th.rowSpan
                ch.tr.style.display = "" if ch.tr.style.display is "none"
                expandChildRow ch
            if h.descendants != 0
                replaceClass h.th, classCollapsed, classExpanded
                h.th.textContent = " " + arrowExpanded + " " + h.th.getAttribute "data-rowHeader"
            h.th.setAttribute "rowspan", rowspan+1
            h.clickStatus = classExpanded
            h.tr.style.display = ""
            p = h.parent
            while p isnt null
                p.th.setAttribute "rowspan", rowspan + parseInt p.th.getAttribute "rowspan"
                p = p.parent
            hh = rowHeaderHeaders.hh[h.col]
            ++hh.expandedCount
            if hh.expandedCount == hh.nHeaders
                replaceClass hh.th, classCollapsed, classExpanded
                hh.th.textContent = " " + arrowExpanded + " " + hh.th.getAttribute "data-rowAttr"
                hh.clickStatus = classExpanded

        toggleCol = (colHeaderHeaders, colHeaderCols, c) ->
            return if not colHeaderCols[c]?

            h = colHeaderCols[c]
            if h.clickStatus is classCollapsed
                expandCol(colHeaderHeaders, colHeaderCols, c)
            else
                collapseCol(colHeaderHeaders, colHeaderCols, c)
            h.th.scrollIntoView

        toggleRow = (rowHeaderHeaders, rowHeaderRows, r) ->
            return if not rowHeaderRows[r]?

            if rowHeaderRows[r].clickStatus is classCollapsed
                expandRow(rowHeaderHeaders, rowHeaderRows, r)
            else
                collapseRow(rowHeaderHeaders, rowHeaderRows, r)

        collapseColsAt = (colHeaderHeaders, colHeaderCols, colAttrs, colAttr) ->
            if typeof colAttr is 'string'
                idx = colAttrs.indexOf colAttr
            else
                idx = colAttr
            return if idx < 0 or idx == colAttrs.length-1
            i = idx
            nAttrs = colAttrs.length-1
            while i < nAttrs
                hh = colHeaderHeaders[i]
                replaceClass hh.th, classExpanded, classCollapsed
                hh.th.textContent = " " + arrowCollapsed + " " + colAttrs[i]
                hh.clickStatus = classCollapsed
                ++i
            i = 0
            nCols = colHeaderCols.length
            while i < nCols
                h = colHeaderCols[i]
                if h.col is idx and h.clickStatus isnt classCollapsed and h.th.style.display isnt "none"
                    collapseCol colHeaderHeaders, colHeaderCols, parseInt h.th.getAttribute("data-node")
                ++i

        expandColsAt = (colHeaderHeaders, colHeaderCols, colAttrs, colAttr) ->
            if typeof colAttr is 'string'
                idx = colAttrs.indexOf colAttr
            else
                idx = colAttr
            return if idx < 0 or idx == colAttrs.length-1
            for i in [0..idx]
                hh = colHeaderHeaders[i]
                replaceClass hh.th, classCollapsed, classExpanded
                hh.th.textContent = " " + arrowExpanded + " " + colAttrs[i]
                hh.clickStatus = classExpanded
                j = 0
                nCols = colHeaderCols.length
                while j < nCols
                    h = colHeaderCols[j]
                    expandCol colHeaderHeaders, colHeaderCols, j if h.col == i
                    ++j
            ++idx
            while idx < colAttrs.length-1
                colHeaderHeader = colHeaderHeaders[idx]
                if colHeaderHeader.expandedCount == 0
                    replaceClass colHeaderHeader.th, classExpanded, classCollapsed
                    colHeaderHeader.th.textContent = " " + arrowCollapsed + " " + colAttrs[idx]
                    colHeaderHeader.clickStatus = classCollapsed
                else if colHeaderHeader.expandedCount == colHeaderHeader.nHeaders
                    replaceClass colHeaderHeader.th, classCollapsed, classExpanded
                    colHeaderHeader.th.textContent = " " + arrowExpanded + " " + colAttrs[idx]
                    colHeaderHeader.clickStatus = classExpanded
                ++idx

        collapseRowsAt = (rowHeaderHeaders, rowHeaderRows, rowAttrs, rowAttr) ->
            if typeof rowAttr is 'string'
                idx = rowAttrs.indexOf rowAttr
            else
                idx = rowAttr

            return if idx < 0 or idx == rowAttrs.length-1

            i = idx
            nAttrs = rowAttrs.length-1
            while i < nAttrs
                h = rowHeaderHeaders.hh[i]
                replaceClass h.th, classExpanded, classCollapsed
                h.th.textContent = " " + arrowCollapsed + " " + rowAttrs[i]
                h.clickStatus = classCollapsed
                ++i
            j = 0
            nRows = rowHeaderRows.length
            while j < nRows
                h = rowHeaderRows[j]
                if h.col is idx and h.clickStatus isnt classCollapsed and h.tr.style.display isnt "none"
                    collapseRow rowHeaderHeaders, rowHeaderRows, j
                    j = j + h.descendants + 1
                else
                    ++j

        expandRowsAt = (rowHeaderHeaders, rowHeaderRows, rowAttrs, rowAttr) ->
            if typeof rowAttr is 'string'
                idx = rowAttrs.indexOf rowAttr
            else
                idx = rowAttr

            return if idx < 0 or idx == rowAttrs.length-1

            for i in [0..idx]
                hh = rowHeaderHeaders.hh[i]
                replaceClass hh.th, classCollapsed, classExpanded
                hh.th.textContent = " " + arrowExpanded + " " + rowAttrs[i]
                hh.clickStatus = classExpanded
                j = 0
                nRows = rowHeaderRows.length
                while j < nRows
                    h = rowHeaderRows[j]
                    if h.col == i
                        expandRow(rowHeaderHeaders, rowHeaderRows, j)
                        j += h.descendants + 1
                    else
                        ++j
            ++idx
            while idx < rowAttrs.length-1
                rowHeaderHeader = rowHeaderHeaders.hh[idx]
                if rowHeaderHeader.expandedCount == 0
                    replaceClass rowHeaderHeader.th, classExpanded, classCollapsed
                    rowHeaderHeader.th.textContent = " " + arrowCollapsed + " " + rowAttrs[idx]
                    rowHeaderHeader.clickStatus = classCollapsed
                else if rowHeaderHeader.expandedCount == rowHeaderHeader.nHeaders
                    replaceClass rowHeaderHeader.th, classCollapsed, classExpanded
                    rowHeaderHeader.th.textContent = " " + arrowExpanded + " " + rowAttrs[idx]
                    rowHeaderHeader.clickStatus = classExpanded
                ++idx

        toggleColHeaderHeader = (colHeaderHeaders, colHeaderCols, colAttrs, colAttr) ->
            idx = colAttrs.indexOf colAttr
            h = colHeaderHeaders[idx]
            if h.clickStatus is classCollapsed
                expandColsAt colHeaderHeaders, colHeaderCols, colAttrs, colAttr
            else
                collapseColsAt colHeaderHeaders, colHeaderCols, colAttrs, colAttr


        toggleRowHeaderHeader = (rowHeaderHeaders, rowHeaderRows, rowAttrs, rowAttr) ->
            idx = rowAttrs.indexOf rowAttr
            th = rowHeaderHeaders.hh[idx]
            if th.clickStatus is classCollapsed
                expandRowsAt rowHeaderHeaders, rowHeaderRows, rowAttrs, rowAttr
            else
                collapseRowsAt rowHeaderHeaders, rowHeaderRows, rowAttrs, rowAttr

        main = (rowAttrs, rowKeys, colAttrs, colKeys) ->
            rowHeaders = []
            colHeaders = []
            rowHeaderHeaders = {}
            rowHeaderRows = []
            colHeaderHeaders = []
            colHeaderCols = []

            rowHeaders = processKeys rowKeys, "pvtRowLabel" if rowAttrs.length > 0 and rowKeys.length > 0
            colHeaders = processKeys colKeys, "pvtColLabel" if colAttrs.length > 0 and colKeys.length > 0

            result = document.createElement "table"
            result.className = "pvtTable"
            result.style.display = "none"

            thead = document.createElement "thead"
            result.appendChild thead

            if colAttrs.length > 0
                buildColHeaderHeaders thead, colHeaderHeaders, rowAttrs, colAttrs
                buildColHeaders colHeaderHeaders, colHeaderCols, h, rowAttrs, colAttrs for h in colHeaders
                buildColHeaderHeadersClickEvents colHeaderHeaders, colHeaderCols, colAttrs

            if rowAttrs.length > 0
                buildRowHeaderHeaders thead, rowHeaderHeaders, rowAttrs, colAttrs
                buildRowTotalsHeader rowHeaderHeaders.tr, rowAttrs, colAttrs if colAttrs.length == 0

            if colAttrs.length > 0
                buildRowTotalsHeader colHeaderHeaders[0].tr, rowAttrs, colAttrs

            tbody = document.createElement "tbody"
            result.appendChild tbody
            buildRowHeaders tbody, rowHeaderHeaders, rowHeaderRows, h, rowAttrs, colAttrs for h in rowHeaders if rowAttrs.length > 0
            buildRowHeaderHeadersClickEvents rowHeaderHeaders, rowHeaderRows, rowAttrs
            buildValues rowHeaderRows, colHeaderCols
            tr = buildColTotalsHeader rowAttrs, colAttrs
            buildColTotals tr, colHeaderCols if colAttrs.length > 0
            buildGrandTotal tbody, tr

            result.setAttribute "data-numrows", rowKeys.length
            result.setAttribute "data-numcols", colKeys.length
            result.style.display = "" if not opts.collapseRowsAt? and not opts.collapseColsAt?
            collapseRowsAt rowHeaderHeaders, rowHeaderRows, rowAttrs, opts.collapseRowsAt if opts.collapseRowsAt?
            if not opts.collapseColsAt?
                result.style.display = ""
                return result
            collapseColsAt colHeaderHeaders, colHeaderCols, colAttrs, opts.collapseColsAt if opts.collapseColsAt?
            result.style.display = ""

            return result

        return main rowAttrs, rowKeys, colAttrs, colKeys

    $.pivotUtilities.subtotal_renderers =
        "Table With Subtotal":  (pvtData, opts) -> SubtotalRenderer pvtData, opts
        "Table With Subtotal Bar Chart":   (pvtData, opts) -> $(SubtotalRenderer pvtData, opts).barchart()
        "Table With Subtotal Heatmap":   (pvtData, opts) -> $(SubtotalRenderer pvtData, opts).heatmap "heatmap", opts
        "Table With Subtotal Row Heatmap":   (pvtData, opts) -> $(SubtotalRenderer pvtData, opts).heatmap "rowheatmap", opts
        "Table With Subtotal Col Heatmap":  (pvtData, opts) -> $(SubtotalRenderer pvtData, opts).heatmap "colheatmap", opts

    usFmtPct = $.pivotUtilities.numberFormat digitsAfterDecimal:1, scaler: 100, suffix: "%"
    aggregatorTemplates = $.pivotUtilities.aggregatorTemplates;

    subtotalAggregatorTemplates =
        fractionOf: (wrapped, type="row", formatter=usFmtPct) -> (x...) -> (data, rowKey, colKey) ->
            rowKey = [] if typeof rowKey is "undefined"
            colKey = [] if typeof colKey is "undefined"
            selector: {row: [rowKey.slice(0, -1),[]], col: [[], colKey.slice(0, -1)]}[type]
            inner: wrapped(x...)(data, rowKey, colKey)
            push: (record) -> @inner.push record
            format: formatter
            value: -> @inner.value() / data.getAggregator(@selector...).inner.value()
            numInputs: wrapped(x...)().numInputs

    $.pivotUtilities.subtotalAggregatorTemplates = subtotalAggregatorTemplates

    $.pivotUtilities.subtotal_aggregators = do (tpl = aggregatorTemplates, sTpl = subtotalAggregatorTemplates) ->
        "Count As Fraction Of Parent Row":      sTpl.fractionOf(tpl.count(), "row", usFmtPct)
        "Count As Fraction Of Parent Column":   sTpl.fractionOf(tpl.count(), "col", usFmtPct)
        "Sum As Fraction Of Parent Row":        sTpl.fractionOf(tpl.sum(), "row", usFmtPct)
        "Sum As Fraction Of Parent Column":     sTpl.fractionOf(tpl.sum(), "col", usFmtPct)

