import $ from "jquery"
import dict from "./dict.coffee"
import message from "./message.coffee"
import storage from "./storage.coffee"
import setting from "./setting.coffee"
import utils from "utils"
import parsers from '../resources/dict-parsers.json'

class LookupParser 
    constructor: (@data) ->
        @typeCount = Object.keys(@data).length
        
    checkType: (w) ->
        for name, dictDesc of @data
            if dictDesc.supportEnglish
                return name if utils.isEnglish(w) and setting.getValue "enableLookupEnglish"
            if dictDesc.supportChinese
                return name if utils.isChinese(w) and setting.getValue "enableLookupChinese"
            if dictDesc.regex
                return name if w.match(new RegExp(dictDesc.regex, 'g'))?.length == w.length

    parse: (w) ->
        tname = @checkType(w)
        return unless tname 

        dictDesc = @data[tname]
        url = dictDesc.url.replace('<word>', w)

        html = $(await $.get url)

        result = @parseResult html, dictDesc.result

        # special handle of bing when look up Chinese
        if tname == "bing"
            if utils.isChinese(w) 
                result.defs = result.defs2 
                delete result.defs2
            else # English 
                if not setting.getValue 'showChineseDefinition'
                    delete result.defs2

        return result

    parseByType: (w, type="ldoce") ->
        dictDesc = @data[type]
        url = dictDesc.url.replace('<word>', w)

        html = $(await $.get url)
        return @parseResult html, dictDesc.result

    parseResult: ($el, obj) ->
        result = {}
        for key, desc of obj
            if Array.isArray desc 
                result[key] = []
                result[key].push @parseResult($el, subObj) for subObj in desc
            else 
                $container = $el 
                if desc.container 
                    $container = $($el.find(desc.container).get(0))

                if desc.groups 
                    result[key] = []
                    $nodes = $container.find desc.groups 
                    $nodes.each (i, el) =>
                        result[key].push @parseResult($(el), desc.result)
                        
                else
                    result[key] = @parseResultItem $container, desc

        return result 

    parseResultItem: ($node, desc) ->
        value = ''

        $el = $node 
        if desc.selector
            $el = $node.find(desc.selector)

        if typeof desc == 'string'
            value = desc 
        else if desc.toArray 
            value = $el.toArray().map (item) -> item.innerText?.trim()
        else if desc.data
            value = $el.data(desc.data)
        else if desc.attr
            value = $el.attr(desc.attr)
        else if desc.htmlRegex
            value = $el.html()?.match(new RegExp(desc.htmlRegex))?[0]
        else
            value = $el.get(0)?.innerText?.trim()
        
        if desc.func 
            _f = new Function(desc.func)
            value = _f.call(this, value)
        
        return value

playAudios = (urls) ->
    return unless urls?.length
    
    _checkEnd = (audio) ->
        if (audio.ended) 
            return true
        
        await utils.promisifiedTimeout 200
        _checkEnd audio

    _play = (url) ->
        new Promise (resolve, reject) ->
            return resolve() if not url

            audio = new Audio(url)
            audio.oncanplay = ()->
                audio.play()
                # console.log url

            _checkEnd(audio).then resolve
    
    for url in urls
        await _play(url)

test = () ->
    parser = new LookupParser(parsers)
    parser.parse('most').then console.log 
    # parser.parse('自由').then console.log 
    # parser.parse('請').then console.log 
    # parser.parse('請う').then console.log 
    # parser.parse('あなた').then console.log 


# test()

export default {
    parser: new LookupParser(parsers),

    init: () ->
        # await @syncDictParsers()

        message.on 'check text supported', ({ w }) =>
            w = w.trim()
            return unless w

            return @parser.checkType(w)
        
        message.on 'look up plain', ({w, s, sc}) =>
            w = w.trim()
            return unless w

            storage.addHistory({
                w, s, sc
            }) if s  # ignore lookup from options page

            return @parser.parse(w) 

        message.on 'get real person voice', ({ w }) =>
            return @parser.parseByType(w)

        message.on 'look up phonetic', ({ w, _counter }) =>
            { prons } = await @parser.parseByType(w, 'bing')
            for n in prons 
                if n.type == 'ame' and n.symbol
                    ame = n.symbol.replace('US', '').trim()
                    return { ame } 

        message.on 'play audios', ({ ameSrc, breSrc, otherSrc, srcs, checkSetting }) ->
            if checkSetting 
                if not setting.getValue 'enableAmeAudio'
                    ameSrc = null
                if not setting.getValue 'enableBreAudio'
                    breSrc = null

                playAudios [ameSrc, breSrc ]
            
            if otherSrc
                playAudios [otherSrc]
            
            if srcs 
                playAudios srcs 

    syncDictParsers: () ->
        errorResult = null 

        src = 'http://localhost:8000/dict-parsers.json'
        data = await $.getJSON(extraSrc).catch (err)->
                console.error "Get parsers remotely failed: ", err.status, err.statusText
                errorResult = { message: err.statusText, error: true }

        @parser = new LookupParser(data)
}