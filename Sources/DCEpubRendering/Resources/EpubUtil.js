//
//  EpubUtil.js
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 4/11/25.
//

(function(){
    'use strict';
    
    // --------------------------------------------------
    // Private state
    // --------------------------------------------------
    const SEL_LEN = 7;
    let isASearch = false;
    let searchString; // used by getPageFromCoords*

    // Set to true to print navigation debug info to the Web Inspector console.
    const NAV_DEBUG = false;
    
    // --------------------------------------------------
    // Environment helpers (no hard jQuery requirement)
    // --------------------------------------------------
    const hasJQ = typeof window.jQuery === 'function';
    const $ = hasJQ ? window.jQuery : null;
    
    function isElementVisible(el){
        if (!el || el.nodeType !== 1) return false;
        const cs = window.getComputedStyle(el);
        if (cs.display === 'none' || cs.visibility === 'hidden' || cs.opacity === '0') return false;
        // Hidden if size is 0 and no children visible
        const rect = el.getBoundingClientRect();
        if (rect.width === 0 && rect.height === 0) {
            // allow inline text nodes within
            let hasVisibleChild = false;
            for (let i = 0; i < el.childNodes.length; i++) {
                const n = el.childNodes[i];
                if (n.nodeType === 1 && isElementVisible(n)) { hasVisibleChild = true; break; }
                if (n.nodeType === 3 && (n.textContent || '').trim().length) { hasVisibleChild = true; break; }
            }
            if (!hasVisibleChild) return false;
        }
        return true;
    }
    
    function offsetOf(el){
        if (!el || el.nodeType !== 1) return { top: 0, left: 0 };
        if (hasJQ && $.fn.offset) return $.fn.offset.call($(el));
        const r = el.getBoundingClientRect();
        const st = window.pageYOffset || document.documentElement.scrollTop || document.body.scrollTop || 0;
        const sl = window.pageXOffset || document.documentElement.scrollLeft || document.body.scrollLeft || 0;
        return { top: r.top + st, left: r.left + sl };
    }
    
    function zeroFilling(number, width) {
        const str = String(number);
        const need = width - str.length;
        if (need > 0) return new Array(need + (/.\./.test(str) ? 2 : 1)).join('0') + str;
        return str;
    }
    
    function childrenFiltered(node, predicate){
        if (!node || !node.childNodes) return [];
        const arr = Array.prototype.slice.call(node.childNodes);
        return arr.filter(predicate);
    }
    
    // --------------------------------------------------
    // Pagination
    // --------------------------------------------------
    function applyHorizontalPagination() {
        const columnGap = 20;
        const stylemargin = 0;

        const d = document.body;
        const scroller = document.scrollingElement || document.documentElement || d;
        const ourH = window.innerHeight;
        const ourW = window.innerWidth;
        const fullH = d.offsetHeight;
        let pageCount = Math.max(1, Math.ceil(fullH / ourH));

        // Leave a small safe inset to avoid clipping descenders at the bottom
        const safeBottomInset = 28;
        d.style.height = `${Math.max(0, ourH - safeBottomInset)}px`;
        d.style.webkitColumnGap = `${columnGap}px`;
        d.style.columnGap = `${columnGap}px`;
        d.style.margin = `${stylemargin}px`;
        d.style.marginLeft = `${stylemargin}px`;
        d.style.textAlign = 'justify';
        d.style.overflow = 'visible';
        d.style.boxSizing = 'content-box';

        // n columns with n-1 gaps in a body one gap narrower than n pages puts every column exactly
        // one page width apart (page p starts at p * innerWidth). The root element keeps the full
        // n pages of width so the last page can be scrolled to as well.
        // Style.css animates every property of <html> (for the old night-mode switch); without
        // this the width below would transition in over 0.6 s instead of applying now.
        document.documentElement.style.transition = 'none';
        document.documentElement.style.webkitTransition = 'none';
        function layoutColumns(count) {
            d.style.width = `${(ourW * count) - columnGap}px`;
            d.style.webkitColumnCount = count;
            document.documentElement.style.minWidth = `${ourW * count}px`;
        }
        layoutColumns(pageCount);

        // The height-based estimate can fall short; overflow columns would end short of a full page.
        // Column width doesn't depend on the count, so re-laying out doesn't reflow the text.
        const measured = Math.max(1, Math.ceil((scroller.scrollWidth - 1) / ourW));
        if (measured > pageCount) {
            pageCount = measured;
            layoutColumns(pageCount);
        }

        return String(pageCount);
    }

    function scrollToLastHorizontalPage() {
        const d = document.scrollingElement || document.documentElement || document.body;
        const pageWidth = window.innerWidth;
        const pageCount = Math.max(1, Math.ceil(d.scrollWidth / pageWidth));
        const totalscroll = (pageCount - 1) * pageWidth;
        d.scrollLeft = totalscroll;
        return totalscroll;
    }
    
    function scrollToFirstPage() { window.scrollTo(0, 0); }

    function scrollToCoordsHorizontal(mark) {
        // getPageFromCoords returns a 0-based page index; no adjustment needed.
        const page = Math.max(0, getPageFromCoords(mark));
        if (NAV_DEBUG) console.log('[Nav] scrollToCoordsHorizontal page=' + page + ' innerWidth=' + window.innerWidth + ' scrollTo=' + (window.innerWidth * page));
        window.scrollTo(window.innerWidth * page, 0);
        return page;
    }

    function scrollToCoordsVertical(mark) {
        // getPageFromCoordsVertical returns a 0-based page index; no adjustment needed.
        const page = Math.max(0, getPageFromCoordsVertical(mark));
        if (NAV_DEBUG) console.log('[Nav] scrollToCoordsVertical page=' + page + ' innerHeight=' + window.innerHeight + ' scrollTo=' + (window.innerHeight * page));
        window.scrollTo(0, window.innerHeight * page);
        return page;
    }
    
    function scrollToFirstHorizontalPage() { return scrollToFirstPage(); }

    // Paged reader helpers. They return Strings because the native bridge only reads String results.
    function getHorizontalPageCount() {
        const d = document.scrollingElement || document.documentElement || document.body;
        const pageWidth = window.innerWidth;
        // Subtract 1px so an exact multiple of the page width doesn't round up to an extra page.
        return String(Math.max(1, Math.ceil((d.scrollWidth - 1) / pageWidth)));
    }

    function getPageFromCoordsHorizontal(mark) {
        return String(Math.max(0, getPageFromCoords(mark)));
    }

    function scrollToHorizontalPage(page) {
        const offset = window.innerWidth * page;
        window.scrollTo(offset, 0);
        return String(offset);
    }

    // Resolves once web fonts have loaded and two frames have been laid out, i.e. when measuring
    // pagination or scroll positions is reliable. WebKit pauses animation frames for web views that
    // aren't in a window, so the frame wait gives up after `frameTimeout` ms; `totalTimeout` caps
    // the whole wait in case a font never finishes loading.
    function waitForLayout(frameTimeout, totalTimeout) {
        const delay = function (ms) { return new Promise(function (resolve) { setTimeout(resolve, ms); }); };
        const frames = new Promise(function (resolve) {
            requestAnimationFrame(function () { requestAnimationFrame(resolve); });
        });
        const fonts = (document.fonts && document.fonts.ready) ? document.fonts.ready : Promise.resolve();
        const settled = fonts.then(function () { return Promise.race([frames, delay(frameTimeout || 100)]); });
        return Promise.race([settled, delay(totalTimeout || 2000)]).then(function () { return 'ready'; });
    }

    function scrollToVerticalPage(page) {
        const offset = window.innerHeight * page;
        window.scrollTo(0, offset);
        return String(offset);
    }

    // 0-based page containing the element with this id (or name), for table-of-contents
    // links like chapter.xhtml#section-2. Returns "-1" when there is no such element.
    function getPageForElementId(id, vertical) {
        const el = document.getElementById(id) || document.getElementsByName(id)[0];
        if (!el) return '-1';
        const offset = offsetOf(el);
        const page = vertical
            ? Math.floor(offset.top / window.innerHeight)
            : Math.floor(offset.left / window.innerWidth);
        return String(Math.max(0, page));
    }

    // --------------------------------------------------
    // Line focus (measurement only; the effect is drawn natively)
    // --------------------------------------------------
    // Rendered text lines inside the viewport, top to bottom, in viewport coordinates (which match
    // the web view's bounds). Returns JSON: { lines: [[x, y, width, height], ...], searchLine: n|-1 }.
    function getVisibleLineRects() {
        const width = window.innerWidth;
        const height = window.innerHeight;
        const rects = [];
        const range = document.createRange();
        searchableTextNodes().forEach(function (node) {
            if (!node.nodeValue.trim()) return;
            range.selectNodeContents(node);
            const list = range.getClientRects();
            for (let i = 0; i < list.length; i++) {
                const r = list[i];
                if (r.width < 1 || r.height < 1) continue;
                if (r.right <= 0 || r.left >= width || r.bottom <= 0 || r.top >= height) continue;
                rects.push(r);
            }
        });
        rects.sort(function (a, b) { return (a.top - b.top) || (a.left - b.left); });

        // Fragments whose vertical midpoint falls inside the previous line belong to it
        // (inline elements, superscripts, highlight spans).
        const lines = [];
        rects.forEach(function (r) {
            const last = lines[lines.length - 1];
            const mid = (r.top + r.bottom) / 2;
            if (last && mid >= last.top && mid <= last.bottom) {
                last.left = Math.min(last.left, r.left);
                last.right = Math.max(last.right, r.right);
                last.top = Math.min(last.top, r.top);
                last.bottom = Math.max(last.bottom, r.bottom);
            } else {
                lines.push({ left: r.left, right: r.right, top: r.top, bottom: r.bottom });
            }
        });

        let searchLine = -1;
        const mark = document.querySelector('.highlight_search');
        if (mark) {
            const r = mark.getBoundingClientRect();
            const mid = (r.top + r.bottom) / 2;
            searchLine = lines.findIndex(function (l) { return mid >= l.top && mid <= l.bottom; });
        }
        return JSON.stringify({
            lines: lines.map(function (l) { return [l.left, l.top, l.right - l.left, l.bottom - l.top]; }),
            searchLine: searchLine
        });
    }

    // --------------------------------------------------
    // Search
    // --------------------------------------------------
    // Body text nodes in document order, skipping <script>/<style>. Their concatenation matches
    // DCHTMLText.bodyText on the native side, so match numbers agree between the two.
    function searchableTextNodes() {
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
            acceptNode: function (node) {
                const parent = node.parentNode ? node.parentNode.nodeName : '';
                return (parent === 'SCRIPT' || parent === 'STYLE') ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT;
            }
        });
        const nodes = [];
        let node;
        while ((node = walker.nextNode())) nodes.push(node);
        return nodes;
    }

    // Wraps the n-th (0-based, non-overlapping, case-insensitive) match of `query` in
    // span.highlight_search and returns the 0-based page that contains it, or "-1" if not found.
    // `highlight_search` is the class the coords helpers (getOffset, getNodePos, filterByClass)
    // already skip, so saved positions and highlights stay valid around search marks.
    function highlightSearchOccurrence(query, occurrence, vertical) {
        if (!query) return '-1';
        const nodes = searchableTextNodes();
        const starts = [];
        let text = '';
        nodes.forEach(function (n) { starts.push(text.length); text += n.nodeValue; });

        const haystack = text.toLowerCase();
        const needle = query.toLowerCase();
        let index = -1;
        let from = 0;
        for (let i = 0; i <= occurrence; i++) {
            index = haystack.indexOf(needle, from);
            if (index < 0) return '-1';
            from = index + needle.length;
        }
        const end = index + needle.length;

        // A match can span several text nodes (e.g. "Moby <b>Di</b>ck"): wrap each piece.
        // Walk backwards so splitting a node doesn't shift the offsets of nodes still to visit.
        let first = null;
        for (let i = nodes.length - 1; i >= 0; i--) {
            const nodeStart = starts[i];
            const nodeEnd = nodeStart + nodes[i].nodeValue.length;
            if (nodeEnd <= index || nodeStart >= end) continue;
            let piece = nodes[i];
            const pieceStart = Math.max(index, nodeStart) - nodeStart;
            const pieceEnd = Math.min(end, nodeEnd) - nodeStart;
            if (pieceEnd < piece.nodeValue.length) piece.splitText(pieceEnd);
            if (pieceStart > 0) piece = piece.splitText(pieceStart);
            const span = document.createElement('span');
            span.className = 'highlight_search';
            span.style.backgroundColor = 'rgba(255, 170, 0, 0.45)';
            span.style.borderRadius = '2px';
            piece.parentNode.insertBefore(span, piece);
            span.appendChild(piece);
            first = span;
        }
        if (!first) return '-1';

        const offset = offsetOf(first);
        const page = vertical
            ? Math.floor(offset.top / window.innerHeight)
            : Math.floor(offset.left / window.innerWidth);
        if (NAV_DEBUG) console.log('[Nav] highlightSearchOccurrence occurrence=' + occurrence + ' page=' + page);
        return String(Math.max(0, page));
    }
    
    function applyVerticalPagination() {
        let margin_top = 40;
        let margin_bottom = 30;
        
        let columnGap = 20;
        let columnGapTop = 40;
        
        let stylemargin = 10;
        
        var d = document.getElementsByTagName('body')[0];
        var ourH = window.innerHeight;
        var ourW = window.innerWidth;
        var fullH = d.offsetHeight;
        var pageCount = 1
        var currentPage = 0;
        d.style.webkitColumnGap = `${columnGap}px`;
        d.style.margin = `${stylemargin}px`;
        d.style.webkitColumnCount = 1;
        d.style.textAlign = 'justify';
        let totalPages = 1;
        return Math.round(totalPages);
    }
    
    function scrollToLastVerticalPage() {
        let stylemargin = 10;
        let columnGap = 20;
        var d = document.getElementsByTagName('body')[0];
        
        let pageHeight = window.innerHeight
        let totalWebHeight = d.offsetHeight
        
        let adjustFinalWeb = d.style.columnCount * (stylemargin + columnGap)
        
        let totalscroll = totalWebHeight+adjustFinalWeb+pageHeight+columnGap+stylemargin+stylemargin;
        
        scrollTo(0, totalscroll)
        return totalscroll
    }
    
    // --------------------------------------------------
    // Coordinates encoding/decoding for nodes
    // --------------------------------------------------
    function getOffset(n, offsetnode) {
        let node = n;
        let offset = 0;
        let previousignored = false;
        
        // If inside a highlight wrapper, shift to wrapper
        if (node && node.nodeType === 3) {
            const p = node.parentNode;
            if (p && (hasClass(p, 'highlight-yellow') || hasClass(p, 'highlight_search') || p.className === 'highlight-underline')) {
                node = p;
                previousignored = true;
            }
        }
        
        while (node && node.previousSibling) {
            node = node.previousSibling;
            const isHL = hasClass(node, 'highlight-yellow') || hasClass(node, 'highlight_search') || node.className === 'highlight-underline';
            if (isHL) {
                offset += getNodeText(node).length;
                previousignored = true;
            } else {
                if (previousignored && node.nodeType === 3) {
                    offset += node.length || getNodeText(node).length;
                    previousignored = false;
                } else {
                    break;
                }
            }
        }
        return offset + (offsetnode || 0);
    }
    
    function hasClass(el, cls){
        if (!el || !el.className) return false;
        if (el.classList) return el.classList.contains(cls);
        return new RegExp('(^|\\s)'+cls+'(\\s|$)').test(el.className);
    }
    function getNodeText(el){ return (el && (el.textContent || el.innerText)) ? (el.textContent || el.innerText) : ''; }
    
    function getNodePos(node, ignore, ignore2) {
        let position = 0;
        let aux = node ? node.previousSibling : null;
        let previousignored = hasClass(node, 'highlight_search') || hasClass(node, ignore) || (node && node.className === ignore2);
        
        while (aux) {
            const notIgnored = !(hasClass(aux, ignore) || hasClass(aux, ignore2) || hasClass(aux, 'highlight_search'));
            if (notIgnored) {
                if (!previousignored && aux.nodeType !== 10) {
                    position++;
                } else if (aux.nodeType === 1) {
                    position++;
                } else if (aux.nextSibling && aux.nextSibling.nextSibling) {
                    const ns = aux.nextSibling.nextSibling;
                    const ok = ns.nodeType === 1 && !(hasClass(ns, 'highlight-yellow') || hasClass(ns, 'highlight_search') || hasClass(ns, 'highlight-underline'));
                    if (ok) position++;
                }
                previousignored = false;
            } else {
                const emptyText = getNodeText(aux).trim() === '';
                if (emptyText && aux.className !== ignore2) {
                    position++;
                } else if (!aux.previousSibling && aux.nextSibling && aux.nextSibling.nodeType === 1) {
                    const ns = aux.nextSibling;
                    const ok = !(hasClass(ns, 'highlight_search') || hasClass(ns, 'highlight-underline') || hasClass(ns, 'highlight-yellow'));
                    if (ok) position++;
                }
                previousignored = true;
            }
            aux = aux.previousSibling;
        }
        return position;
    }
    
    function getCoordFromNode(node, offset) {
        const selParents = [];
        let aux = node;
        selParents.push(zeroFilling(parseInt(getOffset(node, offset), 10), SEL_LEN));
        if (aux && aux.parentNode && (aux.parentNode.className === 'highlight-yellow' || aux.parentNode.className === 'highlight-underline' || aux.parentNode.className === 'highlight_search')) {
            aux = aux.parentNode;
        }
        while (aux && aux.parentNode) {
            const entry = getNodePos(aux, 'highlight-yellow', 'highlight-underline');
            selParents.push(zeroFilling(parseInt(entry, 10), 7));
            aux = aux.parentNode;
        }
        selParents.reverse();
        return selParents.join('>');
    }
    
    function filterByClass(element){
        const re = /(\r\n|\n|\r)/gm;
        if (!isASearch) {
            return (element.nodeType !== 10 && element.className !== 'highlight-yellow' && element.className !== 'highlight-underline' && element.className !== 'highlight_search');
        }
        return (!re.test(element.nodeValue || '') && element.nodeType !== 8 && element.nodeType !== 10 && element.className !== 'highlight-yellow' && element.className !== 'highlight-underline' && element.className !== 'highlight_search');
    }
    
    function getNodeFromCoordFix(mark, ifrDoc) {
        const levels = mark.split(',')[0].split('>');
        let current = ifrDoc;
        for (let i = 0; i < levels.length - 1; i++) {
            const idx = parseInt(levels[i], 10);
            if (!current) break;
            current = current.childNodes[idx];
        }
        isASearch = false;
        return current;
    }
    
    function getNodeFromCoord(mark, ifrDoc) {
        const levels = mark.split(',')[0].split('>');
        let current = ifrDoc;
        let nodesEnd;
        for (let i = 0; i < levels.length - 1; i++) {
            const idx = parseInt(levels[i], 10);
            if (!current) break;
            const nodes = childrenFiltered(current, filterByClass);
            nodesEnd = current.childNodes;
            current = nodes[idx];
        }
        if (nodesEnd && nodesEnd.length > 1) {
            const nodes = childrenFiltered(current ? current.parentNode : null, filterByClass);
            if (nodesEnd.length > nodes.length) {
                let acc = 0;
                for (let i = 0; i < nodesEnd.length; i++) {
                    current = nodesEnd[i];
                    acc += getLengthNode(current);
                    if (acc > parseInt(levels[levels.length - 1], 10)) break;
                }
            }
        }
        if (current) isASearch = false;
        return current;
    }
    
    function getLengthNode(node) {
        const nodes = node && node.childNodes ? node.childNodes : [];
        if (nodes.length > 0) {
            let count = 0;
            for (let i = 0; i < nodes.length; i++) count += getLengthNode(nodes[i]);
            return count;
        }
        return 0;
    }
    
    // --------------------------------------------------
    // Visible node helpers
    // --------------------------------------------------
    function listVisibleNonContainer(){
        // Equivalent to jQuery(':visible').not('body, html, div')
        const all = document.querySelectorAll('body *:not(div)');
        const arr = Array.prototype.slice.call(all);
        return arr.filter(isElementVisible);
    }
    
    function getFirstNodeVisibleHorizontal(page) {
        const arr = hasJQ ? $.makeArray($(':visible').not('body, html, div')) : listVisibleNonContainer();
        let first = undefined;
        for (let i = 0; i < arr.length; i++) {
            const el = arr[i];
            if (!filterByClass(el)) continue;
            if (typeof first === 'undefined') first = el;
            if (offsetOf(el).left >= page * window.innerWidth) { first = el; break; }
        }
        return first || document.body;
    }
    
    function getFirstNodeVisibleVertical(page) {
        const arr = hasJQ ? $.makeArray($(':visible').not('body, html, div')) : listVisibleNonContainer();
        let first = undefined;
        for (let i = 0; i < arr.length; i++) {
            const el = arr[i];
            if (!filterByClass(el)) continue;
            if (typeof first === 'undefined') first = el;
            if (offsetOf(el).top >= page * window.innerHeight) { first = el; break; }
        }
        return first || document.body;
    }
    
    function getCoordsFirstNodeOfPageHorizontal(currentPage) {
        return getCoordFromNode(getFirstNodeVisibleHorizontal(currentPage), 0);
    }
    function getCoordsFirstNodeOfPageVertical(currentPage) {
        return getCoordFromNode(getFirstNodeVisibleVertical(currentPage), 0);
    }
    
    function getCoordsFromSelection() {
        const sel = window.getSelection();
        let anchorCoord = 0, focusCoord = 0;
        try {
            anchorCoord = getCoordFromNode(sel.anchorNode, sel.anchorOffset);
            focusCoord = getCoordFromNode(sel.focusNode, sel.focusOffset);
        } catch (err) { return String(err); }
        return isSelectionBackwards() ? (focusCoord + ',' + anchorCoord) : (anchorCoord + ',' + focusCoord);
    }
    
    function highlightSelection(mark_type) {
        try {
            const text = String(window.getSelection().toString());
            const coords = getCoordsFromSelection();
            return coords + '[QL_GAP]' + text;
        } catch (err) { return String(err); }
    }
    
    function highlightCoords(mark, mark_type, guid, text) {
        try {
            const [iniCoords, endCoords] = mark.split(',');
            const iniOffset = iniCoords.split('>').pop();
            const endOffset = endCoords.split('>').pop();
            
            let tempIniNode = getNodeFromCoord(iniCoords, document);
            let iniNode = getNodeFromCoord(iniCoords, document);
            const iniFixNode = getNodeFromCoordFix(iniCoords, document);
            
            const coordsIniNode = getCoordFromNode(iniNode, 0);
            const coordsIniFixNode = getCoordFromNode(iniFixNode, 0);
            if (!iniNode || !getNodeText(iniNode).includes(text) || coordsIniNode > coordsIniFixNode) iniNode = iniFixNode;
            
            let tempEndNode = getNodeFromCoord(endCoords, document);
            let endNode = getNodeFromCoord(endCoords, document);
            const endFixNode = getNodeFromCoordFix(endCoords, document);
            
            const coordsEndNode = getCoordFromNode(endNode, 0);
            const coordsEndFixNode = getCoordFromNode(endFixNode, 0);
            if (!endNode || !getNodeText(endNode).includes(text) || coordsEndNode > coordsEndFixNode) endNode = endFixNode;
            
            if (!iniNode){ while (tempIniNode && !getNodeText(tempIniNode).includes(text)) tempIniNode = tempIniNode.nextSibling; }
            if (!endNode){ while (tempEndNode && !getNodeText(tempEndNode).includes(text)) tempEndNode = tempEndNode.nextSibling; }
            
            iniNode = iniNode || tempIniNode;
            endNode = endNode || tempEndNode;
            
            displayRange(document, iniNode, parseInt(iniOffset,10), endNode, parseInt(endOffset,10), 1, mark_type, mark, guid);
        } catch (err) { return String(err); }
    }
    
    function isSelectionBackwards() {
        const sel = window.getSelection && window.getSelection();
        if (sel && !sel.isCollapsed) {
            const range = document.createRange();
            range.setStart(sel.anchorNode, sel.anchorOffset);
            range.setEnd(sel.focusNode, sel.focusOffset);
            const backwards = range.collapsed;
            range.detach && range.detach();
            return backwards;
        }
        return false;
    }
    
    function getNumPages() {
        let pages = parseInt(document.width / window.innerWidth, 10);
        if ((document.width / window.innerWidth) - pages > 0) pages++;
        return pages;
    }
    
    function getPageFromCoords(mark) {
        let node = getNodeFromCoord(mark, document) || getNodeFromCoordFix(mark, document);
        if (!node) return 0;
        let leftOffset = offsetOf(node).left;
        if (leftOffset === 0 && node.parentNode) {
            if (hasJQ && !$(node.parentNode).is(':visible')) return -1000;
            leftOffset = offsetOf(node.parentNode).left;
        }
        if (typeof searchString === 'string' && searchString.length) {
            while (node && !getNodeText(node).includes(searchString)) { node = node.nextSibling; leftOffset = offsetOf(node).left; }
            if (hasJQ && node) $(node).highlight(searchString);
        }
        const page = parseInt((leftOffset / window.innerWidth), 10);
        if (NAV_DEBUG) console.log('[Nav] getPageFromCoords leftOffset=' + leftOffset + ' innerWidth=' + window.innerWidth + ' page=' + page);
        return page;
    }
    
    function getPageFromCoordsVertical(mark) {
        let node = getNodeFromCoord(mark, document) || getNodeFromCoordFix(mark, document);
        if (!node) return 0;
        let topOffset = offsetOf(node).top;
        if (topOffset === 0 && node.parentNode) {
            if (hasJQ && !$(node.parentNode).is(':visible')) return -1000;
            topOffset = offsetOf(node.parentNode).top;
        }
        if (typeof searchString === 'string' && searchString.length) {
            while (node && !getNodeText(node).includes(searchString)) { node = node.nextSibling; topOffset = offsetOf(node).top; }
            if (hasJQ && node) $(node).highlight(searchString);
        }
        // Returns the 0-based page index that contains this element.
        // floor(topOffset / innerHeight) gives the page whose top edge is <= the element.
        const page = Math.floor(topOffset / window.innerHeight);
        if (NAV_DEBUG) console.log('[Nav] getPageFromCoordsVertical topOffset=' + topOffset + ' innerHeight=' + window.innerHeight + ' page=' + page);
        return page;
    }
    
    function setBookFontSizeHorizontal(fontSize, pageNumber) {
        try {
            const currentVisibleNode = getFirstNodeVisibleHorizontal(pageNumber);
            const currentNodeCoords = getCoordFromNode(currentVisibleNode, offsetOf(currentVisibleNode).left);
            if (hasJQ) $('body,table').css('font-size', fontSize);
            else document.body.style.fontSize = fontSize;
            const newPageNumber = getPageFromCoords(currentNodeCoords);
            const newNumPages = getNumPages();
            window.scrollTo(window.innerWidth * newPageNumber, 0);
            return newPageNumber + '-' + newNumPages;
        } catch (err) { return '0-0'; }
    }
    
    function getBookFontSize() {
        if (hasJQ) return String($('body').css('font-size')).split('px')[0];
        const v = window.getComputedStyle(document.body).fontSize || '0px';
        return v.replace('px','');
    }
    
    function displayMode(mode) {
        // Legacy behavior relies on CSS classes; if no jQuery, do a best-effort
        const apply = (el, remove, add)=>{
            remove.forEach(c=> el.classList.remove(c));
            if (add) el.classList.add(add);
        };
        const all = document.querySelectorAll('*');
        switch (mode) {
            case 0: all.forEach(el=>apply(el,['night','sepia','grey'])); break;
            case 1: all.forEach(el=>apply(el,['sepia','grey'],'night')); break;
            case 2: all.forEach(el=>apply(el,['night','sepia'],'grey')); break;
            case 3: all.forEach(el=>apply(el,['night','grey'],'sepia')); break;
            default: all.forEach(el=>apply(el,['night','sepia','grey'])); break;
        }
    }
    
    function getElementsBetweenTree(start, end) {
        if (!start || !end) return null;
        const ancestor = getCommonAncestor(start, end);
        const before = [start];
        let s = start;
        while (s.parentNode !== ancestor) {
            let el = s; while (el.nextSibling) before.push(el = el.nextSibling);
            s = s.parentNode;
        }
        const after = [];
        let e = end;
        while (e.parentNode !== ancestor) {
            let el = e; while (el.previousSibling) after.push(el = el.previousSibling);
            e = e.parentNode;
        }
        after.reverse();
        while ((s = s.nextSibling) !== e) before.push(s);
        before.push(e);
        return before.concat(after);
    }
    
    function getCommonAncestor(a, b) {
        // Vanilla alternative to $(a).parents().andSelf().index(b)
        const parents = [];
        let cur = a; while (cur) { parents.push(cur); cur = cur.parentNode; }
        while (b) { if (parents.indexOf(b) !== -1) return b; b = b.parentNode; }
        return null;
    }
    
    function highlightSearchResult(mark, term) {
        isASearch = true; searchString = term;
        const node = getNodeFromCoord(mark, document) || getNodeFromCoordFix(mark, document);
        if (hasJQ && node) $(node).highlight(term);
    }
    
    function displayRange(doc, anchorNode, anchorOffset, focusNode, focusOffset, id, cl, coords, guid) {
        if (!checkIfValid(anchorNode, anchorOffset, focusNode, focusOffset)) return false;
        if (anchorNode === focusNode) { displaySelectionText(anchorNode, anchorOffset, focusNode, focusOffset, cl, coords, guid); return true; }
        const nodes = getElementsBetweenTree(anchorNode, focusNode) || [];
        try {
            displaySelectionText(anchorNode, anchorOffset, anchorNode, (anchorNode.nodeValue || '').length, cl, coords, guid);
            displaySelectionText(focusNode, 0, focusNode, focusOffset, cl, coords, guid);
        } catch (_) {}
        for (let i = 0; i < nodes.length; i++) {
            const el = nodes[i];
            if (el === anchorNode || el === focusNode) continue;
            // skip if ancestor of endpoints
            let cur = anchorNode; let skip = false; while (cur){ if (cur === el) { skip = true; break; } cur = cur.parentNode; }
            cur = focusNode; while (!skip && cur){ if (cur === el) { skip = true; break; } cur = cur.parentNode; }
            if (skip) continue;
            const cls = (cl === 'highlight-yellow') ? 'highlight-yellow' : (cl === 'highlight-underline') ? 'highlight-underline' : 'highlight_search';
            if (el.nodeType === 3) {
                const span = document.createElement('span'); span.className = cls; el.parentNode.insertBefore(span, el); span.appendChild(el);
            } else {
                const span = document.createElement('span'); span.className = cls; while (el.firstChild) span.appendChild(el.firstChild); el.appendChild(span);
            }
            const nodeClickable = getNodeFromCoord(coords, document);
            if (nodeClickable) {
                nodeClickable.removeEventListener('click', nodeClickable.__epub_click, false);
                nodeClickable.__epub_click = function(){ window.location = 'digitalbooks://clicks/' + cl + '/' + coords; };
                nodeClickable.addEventListener('click', nodeClickable.__epub_click, false);
            }
        }
        return true;
    }
    
    function checkIfValid(anchorNode, anchorOffset, focusNode, focusOffset) {
        const invalid = (n)=> n && n.parentNode && (n.parentNode.className === 'highlight-yellow' || n.parentNode.className === 'highlight_search' || n.parentNode.className === 'highlight-underline');
        return !(invalid(anchorNode) || invalid(focusNode));
    }
    
    function displaySelectionText(iniNode, iniOffset, endNode, endOffset, cl, coords, guid) {
        const selectionRange = document.createRange();
        selectionRange.setStart(iniNode, iniOffset);
        selectionRange.setEnd(endNode, endOffset);
        const highlightNode = document.createElement('span');
        highlightNode.className = (cl === 'highlight-yellow') ? 'highlight-yellow' : (cl === 'highlight-underline') ? 'highlight-underline' : 'highlight_search';
        highlightNode.setAttribute('id', guid);
        highlightNode.setAttribute('onclick', 'callHighlightURL(this);');
        selectionRange.surroundContents(highlightNode);
    }
    
    function setFontFaceHorizontal(fontFace, pageNumber) {
        try {
            const currentVisibleNode = getFirstNodeVisibleHorizontal(pageNumber);
            const currentNodeCoords = getCoordFromNode(currentVisibleNode, offsetOf(currentVisibleNode).left);
            if (hasJQ) $('*').css('font-family', fontFace); else document.body.style.fontFamily = fontFace;
            const newPageNumber = getPageFromCoords(currentNodeCoords);
            const newNumPages = getNumPages();
            window.scrollTo(window.innerWidth * newPageNumber, 0);
            return newPageNumber + '-' + newNumPages;
        } catch (err) { return '0-0'; }
    }
    
    // jQuery highlight plugin (only if jQuery exists; core does not depend on it)
    if (hasJQ) {
        $.extend({
            highlight: function (node, re, nodeName, className) {
                if (node.nodeType === 3) {
                    const match = node.data.match(re);
                    if (match) {
                        const highlight = document.createElement(nodeName || 'span');
                        highlight.className = className || 'highlight_search';
                        const wordNode = node.splitText(match.index);
                        wordNode.splitText(match[0].length);
                        const wordClone = wordNode.cloneNode(true);
                        highlight.appendChild(wordClone);
                        wordNode.parentNode.replaceChild(highlight, wordNode);
                        return 1;
                    }
                } else if ((node.nodeType === 1 && node.childNodes) && !/(script|style)/i.test(node.tagName) && !(node.tagName === (nodeName || '').toUpperCase() && node.className === (className || ''))) {
                    for (let i = 0; i < node.childNodes.length; i++) { i += $.highlight(node.childNodes[i], re, nodeName, className); }
                }
                return 0;
            }
        });
        
        $.fn.unhighlight = function (options) {
            const settings = { className: 'highlight_search', element: 'span' };
            $.extend(settings, options);
            return this.find(settings.element + '.' + settings.className).each(function () {
                const parent = this.parentNode; parent.replaceChild(this.firstChild, this); parent.normalize();
            }).end();
        };
        
        $.fn.highlight = function (words, options) {
            const settings = { className: 'highlight_search', element: 'span', caseSensitive: false, wordsOnly: false };
            $.extend(settings, options);
            if (words.constructor === String) words = [words];
            words = $.grep(words, function(word){ return word !== ''; });
            words = $.map(words, function(word){ return word.replace(/[-[\]{}()*+?.,\\^$|#\s]/g, "\\$&"); });
            if (words.length === 0) return this;
            const flag = settings.caseSensitive ? '' : 'i';
            let pattern = '(' + words.join('|') + ')';
            if (settings.wordsOnly) pattern = '\\b' + pattern + '\\b';
            const re = new RegExp(pattern, flag);
            return this.each(function(){ $.highlight(this, re, settings.element, settings.className); });
        };
    }
    
    function getPageForNodeID(nodeID){
        const nodeSelected = document.getElementById(nodeID);
        if (!nodeSelected) return '';
        const currentNodeCoords = getCoordFromNode(nodeSelected, offsetOf(nodeSelected).left);
        const nodeIDPage = getPageFromCoords(currentNodeCoords);
        window.scrollTo(window.innerWidth * nodeIDPage, 0);
        return currentNodeCoords;
    }
    
    function rectsForSelection() {
        const allSelections = window.getSelection();
        const result = [];
        for (let i = 0; i < allSelections.rangeCount; i++) {
            const aRange = allSelections.getRangeAt(i);
            const rects = aRange.getClientRects();
            for (let j = 0; j < rects.length; j++) result.push(rects[j]);
        }
        return JSON.stringify(result);
    }
    
    function clearTextSelection() {
        const sel = window.getSelection && window.getSelection();
        if (!sel) return;
        if (sel.empty) sel.empty();
        else if (sel.removeAllRanges) sel.removeAllRanges();
        else if (document.selection) document.selection.empty();
    }
    
    // --------------------------------------------------
    // Selection bridge (same API, minor cleanups)
    // --------------------------------------------------
    (function(){
        const HANDLER = 'selectionChanged';
        function installSelectionBridge() {
            if (window.__dc_selection_listener) document.removeEventListener('selectionchange', window.__dc_selection_listener, true);
            let lastKey = '';
            let lastSentAt = 0;
            let to = null;
            const buildKey = (sel)=> sel && sel.rangeCount ? sel.toString() : '';
            function notify(){
                try{
                    const sel = window.getSelection();
                    const text = sel ? sel.toString() : '';
                    const now = Date.now();
                    if (!text){
                        const key = '';
                        if (lastKey !== key || (now - lastSentAt) > 250){
                            if (window.webkit?.messageHandlers?.[HANDLER]) window.webkit.messageHandlers[HANDLER].postMessage({ text: '' });
                            lastKey = key; lastSentAt = now;
                        }
                        return;
                    }
                    const key = buildKey(sel);
                    if (key === lastKey && (now - lastSentAt) < 250) return;
                    if (window.webkit?.messageHandlers?.[HANDLER]) window.webkit.messageHandlers[HANDLER].postMessage({ text });
                    lastKey = key; lastSentAt = now;
                } catch (_) {}
            }
            function debounced(){ if (to) clearTimeout(to); to = setTimeout(notify, 120); }
            document.addEventListener('selectionchange', debounced, true);
            window.__dc_selection_listener = debounced;
        }
        if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', installSelectionBridge, { once: true });
        else installSelectionBridge();
        window.EpubUtil = window.EpubUtil || {};
        window.EpubUtil.installSelectionBridge = installSelectionBridge;
    })();
    
    // --------------------------------------------------
    // Public API (preserve legacy globals)
    // --------------------------------------------------
    const API = {
        applyHorizontalPagination,
        scrollToLastHorizontalPage,
        scrollToFirstHorizontalPage,
        getHorizontalPageCount,
        getPageFromCoordsHorizontal,
        scrollToHorizontalPage,
        scrollToVerticalPage,
        waitForLayout,
        highlightSearchOccurrence,
        getVisibleLineRects,
        getPageForElementId,
        scrollToCoordsHorizontal,
        scrollToCoordsVertical,
        applyVerticalPagination,
        scrollToLastVerticalPage,
        getCoordFromNode,
        getOffset,
        getNodePos,
        zeroFilling,
        getNodeFromCoordFix,
        getNodeFromCoord,
        getLengthNode,
        filterByClass,
        getFirstNodeVisibleHorizontal,
        getFirstNodeVisibleVertical,
        getCoordsFirstNodeOfPageHorizontal,
        getCoordsFirstNodeOfPageVertical,
        getCoordsFromSelection,
        highlightSelection,
        highlightCoords,
        isSelectionBackwards,
        getNumPages,
        getPageFromCoords,
        getPageFromCoordsVertical,
        setBookFontSizeHorizontal,
        getBookFontSize,
        displayMode,
        getElementsBetweenTree,
        getCommonAncestor,
        highlightSearchResult,
        displayRange,
        checkIfValid,
        displaySelectionText,
        setFontFaceHorizontal,
        getPageForNodeID,
        scrollToFirstPage,
        rectsForSelection,
        clearTextSelection
    };
    
    window.EpubUtil = window.EpubUtil || {};
    window.EpubUtil.core = API;
    Object.keys(API).forEach(k => { window[k] = API[k]; });
})();
