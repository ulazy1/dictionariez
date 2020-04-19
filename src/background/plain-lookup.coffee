import $ from "jquery"
import dict from "./dict.coffee"
import message from "./message.coffee"
import storage from "./storage.coffee"
import setting from "./setting.coffee"
import utils from "utils"

parseLdoceonlineAudios = (word) ->
    dres = await dict.query(word, 'Longman English')
    res = await $.get(dres.windowUrl)
    nodes = $(res)

    prons = {}
    w = nodes.find('.ldoceEntry .Head .HYPHENATION').text()
    ameSrc = nodes.find('.ldoceEntry .Head .amefile').attr('data-src-mp3')
    breSrc = nodes.find('.ldoceEntry .Head .brefile').attr('data-src-mp3')
    # console.log(w, ameSrc, breSrc)
    return {ameSrc, breSrc}
    

# most: 这个单词的 E-E 词典有 gl_none 这个 class；
# 词组: 查询词组时没有音标，只有发音；
# 网络词汇可能只有 web 释义，没有发音，如： https://cn.bing.com/dict/search?q=wantonly
# 中文词： 查询结果上部是英文翻译，E-E 的地方却是 cn-cn, 如： https://cn.bing.com/dict/search?q=%E5%A4%A7%E5%8D%8A
parseBing = (word) ->
    dres = await dict.query(word, "Bing Dict (必应词典)")
    res = await $.get(dres.windowUrl)
    nodes = $(res)
    # console.log(nodes.find('.hd_pr').text())
    # console.log(nodes.find('.hd_prUS').text())

    w = nodes.find('.hd_area #headword').text()

    prons = {
        ame: nodes.find('.hd_area .hd_prUS').text(),
        ameAudio: nodes.find('.hd_area .hd_prUS').next('.hd_tf').html()?.match(/https:.*?\.mp3/)[0]
        bre: nodes.find('.hd_area .hd_pr').text(),
        breAudio: nodes.find('.hd_area .hd_pr').next('.hd_tf').html()?.match(/https:.*?\.mp3/)[0]
    }

    # replace audios with ldoceonline sources.
    if w and prons.ame and not utils.hasChinese(w)
        { ameSrc, breSrc } = await parseLdoceonlineAudios(w)
        prons.ameAudio = ameSrc if ameSrc
        prons.breAudio = breSrc if breSrc

    if prons.ame
        prons.ame = prons.ame.replace('美', 'Ame')
        prons.bre = prons.bre.replace('英', 'Bre')

    enDefs = []

    eeNodes = nodes.find('#homoid tr.def_row')
    eeNodes.each (i, el) ->
        enDefs.push({
            pos: $(el).find('.pos').text(),
            def: $(el).find('.def_fl .de_li1')
                # https://cn.bing.com/dict/search?q=most 这个单词有 gl_none 的特例;
                .filter(() -> !$(this).parent().hasClass('gl_none'))
                .toArray().map (item) -> item.innerText
        })

    cnDefs = []

    if setting.getValue 'showChineseDefinition'
        defsNodes = nodes.find('.qdef ul')
        defsNodes.find('.pos').each (i, el) ->
            cnDefs.push({
                pos: $(el).text(),
                def: $(el).next().text()
            })

    # console.log prons, enDefs, cnDefs
    return {en: enDefs, cn: cnDefs, prons, w}

parseJapanese = (w) ->
    url = "https://www.japandict.com/#{w}"
    res = await $.get(url)
    nodes = $(res)

    prons = {}
    pronsNode = nodes.find('h2:contains("Pronunciation")').next().next().next()
    list = pronsNode.find('.list-group-item')
    list.each (i, listItem) ->
        pron = $(listItem).find('.small').text()
        data = $(listItem).find('.small').next().data('reading')

        pronAudio = "https:#{data[0]}/read?text=#{data[1]}&outputFormat=ogg_vorbis&jwt=#{data[2]}"
        prons = { pron, pronAudio }

    results = []
    labels = []
    def = []

    defsNode = nodes.find('.m-t-3:contains("Translation")').next().next()
    list = defsNode.find('.list-group-item')
    list.each (i, listItem) ->
        # only english tab
        return unless $(listItem).children('[lang="en"]').length
        items = $(listItem).children()
        items.each (i, node) ->
            if $(node).find('.label').length
                if labels.length
                    results.push { labels, def }
                    labels = []
                    def = []

                $('.label', node).each (i, label) ->
                    labels.push $(label).text()
                    console.log $(label).text()

            else if not $(node).hasClass('p-l-1')
                text = $(node).text().trim()
                def.push text if text

    if labels.length
        results.push { labels, def }

    console.log "parse japanese: ", { en: results, prons }
    return { en: results, prons }

message.on 'look up plain', ({w, s, sc})->
    w = w.trim()
    return unless w
    storage.addHistory({
        w, s, sc
    }) if s  # ignore lookup from options page

    if utils.hasJapanese(w) and setting.getValue "enableLookupJapanese"
        return parseJapanese(w)

    
    return parseBing(w)


# parseBing('https://cn.bing.com/dict/search?q=most')
# parseJapanese('です')
# parseJapanese('も')
# parseJapanese('怖がる')