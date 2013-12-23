-- This is a JATS custom writer for pandoc.  It produces output
-- that tries to conform to the JATS 1.0 specification
-- http://jats.nlm.nih.gov/archiving/tag-library/1.0/index.html
--
-- Invoke with: pandoc -t JATS.lua
--
-- Note:  you need not have lua installed on your system to use this
-- custom writer.  However, if you do have lua installed, you can
-- use it to test changes to the script.  'lua JATS.lua' will
-- produce informative error messages if your code contains
-- syntax errors.
--
-- Released under the GPL, version 2 or greater. See LICENSE for more info.

-- XML character entity escaping
function escape(s)
  local map = { ['<'] = '&lt;',
                ['>'] = '&gt;',
                ['&'] = '&amp;',
                ['"'] = '&quot;',
                ['\'']= '&#39;' }
  return s:gsub("[<>&\"']", function(x) return map[x] end)
end

-- Helper function to convert an attributes table into
-- a string that can be put into XML elements.
function attributes(attr)
  local attr_table = {}
  for x,y in pairs(attr) do
    if y and y ~= "" then
      table.insert(attr_table, string.format(' %s="%s"', x, escape(y)))
    end
  end
  return table.concat(attr_table)
end

-- Flatten nested table, needed for nested YAML metadata.
-- We only flatten associative arrays and create composite key,
-- numbered arrays and flat tables are left intact.
function flatten_table(tbl)
  local result = {}

  local function flatten(tbl, key)
    for k, v in pairs(tbl) do
      if type(k) == 'number' and k > 0 and k <= #tbl then
        result[key] = tbl
        break
      else
        k = (key and key .. '_' or '') .. k
        if type(v) == 'table' then
          flatten(v, k)
        else
          result[k] =  v
        end
      end
    end
  end

  flatten(tbl)
  return result
end

-- Find a template and return its contents (or '' if
-- not found). The template is sought first in the
-- working directory, then in `templates`.
function find_template(name)
  local base, ext = name:match("([^%.]*)(.*)")
  local fname = base .. ext
  local file = io.open(fname, "read")
  if not file then
    file = io.open("templates/" .. fname, "read")
  end
  if file then
    return file:read("*all")
  else
    return '$body$'
  end
end

-- String substitution for Pandoc templates,
-- observing if/endif, for/endfor and variable attributes.
function fill_template(template, data)

  --patterns
  condition_pattern = '%$if%(([%a_][%w_]*%.*[%w_]*)%)%$\n(.-)%$endif%$'
  loop_pattern = '%$for%(([%a_][%w_]*)%)%$\n(.-)%$endfor%$'

  -- check conditionals
  template = template:gsub(condition_pattern, function(tag, s)
               return data[tag] and s or ''
             end)

  -- check loops
  template = template:gsub(loop_pattern, function(tag, s)
               r = ''
               if data[tag] then
                 for _, t in pairs(data[tag]) do
                   r = r .. fill_template(s, { [tag] = t })
                 end
               end
               return r
             end)

  -- remove extra whitespace
  template = template:gsub('[\n      ]+\n', '\n')

  -- insert values and attributes
  return template:gsub('%$([%a_][%w_]*)%$', function(w) return data[w] or '' end)
end

-- Convert pandoc alignment to something HTML can use.
-- align is AlignLeft, AlignRight, AlignCenter, or AlignDefault.
function html_align(align)
  if align == 'AlignRight' then
    return 'right'
  elseif align == 'AlignCenter' then
    return 'center'
  else
    return 'left'
  end
end

-- The following code will produce runtime warnings when you haven't defined
-- all of the functions you need for the custom writer, so it's useful
-- to include when you're working on a writer.
local meta = {}
meta.__index =
  function(_, key)
    io.stderr:write(string.format("WARNING: Undefined function '%s'\n",key))
    return function() return "" end
  end
setmetatable(_G, meta)

-- Table to store footnotes, so they can be included at the end.
local notes = {}

-- This function is called once for the whole document. Parameters:
-- body is a string, metadata is a table, variables is a table.
function Doc(body, metadata, variables)

  local offset = body:find('<ref-')
  if (offset == nil) then
    back = ''
  else
    back = body:sub(offset)
    body = body:sub(1, offset - 1)
  end

  body = string.format('<sec>\n<title/>%s</sec>\n', body)

  local data = metadata or {}
  data.body = body
  data.back = back

  -- metadata groups
  article = metadata['article'] or {}
  journal = metadata['journal'] or {}
  copyright = metadata['copyright'] or {}

  -- variables required for validation
  data.article_publisher_id = article['publisher-id']
  data.article_doi = article['doi']
  data.article_pmid = article['pmid']
  data.article_pmcid = article['pmcid']
  data.article_art_access_id = article['art-access-id']
  if not (article['publisher-id'] or article['doi'] or article['pmid'] or article['pmcid'] or article['art-access-id']) then
    data.article_art_access_id = ''
  end
  data.journal_pissn = journal['pissn']
  data.journal_eissn = journal['eissn']
  if not (journal['pissn'] or journal['eissn']) then journal['eissn'] = '' end
  data.journal_publisher_id = journal['publisher-id']
  data.journal_nlm_ta = journal['nlm-ta']
  data.journal_pmc = journal['pmc']
  if not (journal['publisher-id'] or journal['nlm-ta'] or journal['pmc']) then
    data.journal_publisher_id = ''
  end

  -- defaults
  data.journal_title = journal['title'] or ''

  data.article_type = article['type'] or 'research-article'
  data.article_heading = article['heading'] or 'Other'
  data.article_category = article['category']
  data.article_elocation_id = article['elocation-id'] or article['doi'] or 'Other'
  data.article_title = metadata['title'] or 'Other'

   -- use today's date if no pub-date in ISO 8601 format is given
  if (article['pub-date'] and string.len(article['pub-date']) == 10) then
    data.article_pub_date = article['pub-date']
  else
    data.article_pub_date = os.date('%Y-%m-%d')
  end

  -- data.author = metadata['author']

  template = find_template('default.jats')
  result = fill_template(template, data)
  return result
end

-- Blocksep is used to separate block elements.
function Blocksep()
  return "\n\n"
end

-- The functions that follow render corresponding pandoc elements.
-- s is always a string, attr is always a table of attributes, and
-- items is always an array of strings (the items in a list).
-- Comments indicate the types of other variables.
-- Defined at https://github.com/jgm/pandoc/blob/master/src/Text/Pandoc/Writers/Custom.hs

-- block elements

function Plain(s)
  return s
end

function CaptionedImage(src, tit, s)
  -- if s begins with <bold> text, make it the <title>
  s = string.gsub('<p>' .. s, "^<p><bold>(.-)</bold>%s", "<title>%1</title>\n<p>")
  return '<fig>\n' ..
         '<caption>\n' .. s .. '</p>\n</caption>\n' ..
         "<graphic mimetype='image' xlink:href='".. escape(src) .. "' xlink:type='simple'/>\n" ..
         '</fig>'
end

function Para(s)
  return "<p>" .. s .. "</p>"
end

function RawBlock(s)
  return "<preformat>" .. s .. "</preformat>"
end

-- JATS restricts use to inside table cells (<td> and <th>)
function HorizontalRule()
  return "<hr/>"
end

-- lev is an integer, the header level.
function Header(lev, s, attr)
  if attr.id and string.match(' ' .. attr.id .. ' ',' references ') then
    return ''
  elseif attr.id then
    return '</sec>\n<sec id="' .. attr.id .. '">\n' ..
           '<title>' .. s .. '</title>'
  else
    return '</sec>\n<sec>\n' ..
           '<title>' .. s .. '</title>'
  end
end

function CodeBlock(s, attr)
  return '<preformat>' .. escape(s) .. '</preformat>'
end

function BlockQuote(s)
  return "<boxed-text>\n" .. s .. "\n</boxed-text>"
end

-- Caption is a string, aligns is an array of strings,
-- widths is an array of floats, headers is an array of
-- strings, rows is an array of arrays of strings.
function Table(caption, aligns, widths, headers, rows)
  local buffer = {}
  local function add(s)
    table.insert(buffer, s)
  end
  table.insert(buffer, '<table-wrap>\n')
  if caption ~= "" then
    -- if caption begins with <bold> text, make it the <title>
    caption = string.gsub('<p>' .. caption, "^<p><bold>(.-)</bold>%s", "<title>%1</title>\n<p>")
    add('<caption>\n' .. caption .. '</p>\n</caption>\n')
  end
  add("<table>")
  if widths and widths[1] ~= 0 then
    for _, w in pairs(widths) do
      add('<col width="' .. string.format("%d%%", w * 100) .. '" />')
    end
  end
  local header_row = {}
  local empty_header = true
  for i, h in pairs(headers) do
    local align = html_align(aligns[i])
    table.insert(header_row,'<th align="' .. align .. '">' .. h .. '</th>')
    empty_header = empty_header and h == ""
  end
  if empty_header then
    head = ""
  else
    add('<tr>')
    for _,h in pairs(header_row) do
      add(h)
    end
    add('</tr>')
  end
  for _, row in pairs(rows) do
    add('<tr>')
    for i,c in pairs(row) do
      -- remove <p> tag
      c = c:gsub("^<p>(.-)</p>", "%1")
      add('<td align="' .. html_align(aligns[i]) .. '">' .. c .. '</td>')
    end
    add('</tr>')
  end
  add('</table>\n</table-wrap>')
  return table.concat(buffer,'\n')
end

function BulletList(items)
  local buffer = {}
  for _, item in pairs(items) do
    table.insert(buffer, '<list-item><p>' .. item .. '</p></list-item>')
  end
  return '<list list-type="bullet">\n' .. table.concat(buffer, '\n') .. '\n</list>'
end

function OrderedList(items)
  local buffer = {}
  for _, item in pairs(items) do
    table.insert(buffer, '<list-item><p>' .. item .. '</p></list-item>')
  end
  return '<list list-type="order">\n' .. table.concat(buffer, '\n') .. '\n</list>'
end

-- Revisit association list STackValue instance.
function DefinitionList(items)
  local buffer = {}
  for _,item in pairs(items) do
    for k, v in pairs(item) do
      table.insert(buffer, '<def-item>\n<term>' .. k .. '</term>\n<def>' ..
                        table.concat(v,'</def>\n<def>') .. '</def>\n</def-item>')
    end
  end
  return '<def-list>\n' .. table.concat(buffer, '\n') .. '\n</def-list>'
end

function Div(s, attr)
  -- parse references
  if attr.class and string.match(' ' .. attr.class .. ' ',' references ') then
    local i = 0
    s = s:gsub("<p>(.-)</p>", function (c)
          i = i + 1
          return '<ref id="ref-' .. i .. '">\n<mixed-citation>' .. c .. '</mixed-citation>\n</ref>'
        end)
    return '<ref-list>\n<title>References</title>\n' .. s .. '\n</ref-list>'
  else
    return s
  end
end

-- inline elements

function Str(s)
  return escape(s)
end

function Space()
  return " "
end

function Emph(s)
  return "<italic>" .. s .. "</italic>"
end

function Strong(s)
  return "<bold>" .. s .. "</bold>"
end

function Strikeout(s)
  return '<strike>' .. s .. '</strike>'
end

function Superscript(s)
  return "<sup>" .. s .. "</sup>"
end

function Subscript(s)
  return "<sub>" .. s .. "</sub>"
end

function SmallCaps(s)
  return "<sc>" .. s .. "</sc>"
end

function SingleQuoted(s)
  return "'" .. s .. "'"
end

function DoubleQuoted(s)
  return '"' .. s .. '"'
end

function Cite(s)
  return '<xref ref-type="bibr">' .. s .. '</xref>'
end

function Code(s, attr)
  return "<preformat>" .. escape(s) .. "</preformat>"
end

function DisplayMath(s)
  return '<disp-formula>' .. escape(s) .. '</disp-formula>'
end

function InlineMath(s)
  return '<inline-formula>' .. escape(s) .. '</inline-formula>'
end

function RawInline(format, s)
  return "<preformat>" .. s .. "</preformat>"
end

function LineBreak()
  return "<br/>"
end

function Link(s, src, tit)
  return '<ext-link ext-link-type="uri" xlink:href="' .. escape(src) .. '" xlink:type="simple">' .. s .. '</ext-link>'
end

function Image(src, tit, s)
  -- if s begins with <bold> text, make it the <title>
  s = string.gsub('<p>' .. s, "^<bold>(.-)</bold>%s", "<title>%1</title>\n<p>")
  return '<fig>\n' ..
         '<caption>\n' .. s .. '</p>\n</caption>\n' ..
         "<graphic mimetype='image' xlink:href='".. escape(src) .. "' xlink:type='simple'/>\n" ..
         '</fig>'
end

function Note(s)
  local num = #notes + 1
  -- insert the back reference right before the final closing tag.
  s = s:gsub('(.*)</', '%1 <a href="#fnref' .. num ..  '">&#8617;</a></')
  -- add a list item with the note to the note table.
  table.insert(notes, '<fn id="fn' .. num .. '">' .. s .. '</fn>')
  -- return the footnote reference, linked to the note.
  return '<a id="fnref' .. num .. '" href="#fn' .. num ..
            '"><sup>' .. num .. '</sup></a>'
end

function Span(s, attr)
  return s
end