from feedgen.feed import FeedGenerator
from markdown_it import MarkdownIt

md = MarkdownIt("gfm-like")

def parse_all_tables(tokens: list):
    table = None
    row = None
    inline_is_data = False
    data = None
    for token in tokens:
        # print(f"token: {token}")

        if not isinstance(token, object):
            print(f"Weird token: {token}")
            continue
        if token.type == "tbody_open":
            table = []
        elif token.type == "tbody_close":
            yield table
            table = None
        elif token.type == "tr_open" and table is not None:
            row = []
        elif token.type == "tr_close" and table is not None:
            table.append(row)
            row = None
        elif token.type == "td_open" and row is not None:
            inline_is_data = True
        elif token.type == "td_close" and row is not None:
            inline_is_data = False
            row.append(data)
        elif token.type == "inline" and inline_is_data:
            if len(token.children) > 1:
                data = token.children
            else:
                data = token.content

fg = FeedGenerator()
fg.title('Opinionated Debian Installer')
fg.description('Alternative debian installer for laptops and desktop PCs')
fg.link(href="https://github.com/r0b0/debian-installer", rel="alternate")
fg.link(href="https://objectstorage.eu-frankfurt-1.oraclecloud.com/n/fr2rf1wke5iq/b/public/o/feed.xml", rel="self")

with open('README.md') as f:
    for table in parse_all_tables(md.parse(f.read())):
        # print(f"table: {table} rows: {len(table)}")
        if len(table) > 3:
            continue
        for row in table:
            fe = fg.add_entry()
            fe.title(f"{row[0]} - {row[1]}")
            url = row[3][0].attrs["href"]
            fe.link(href=url)
            fe.guid(url)

fg.rss_file("feed.xml", pretty=True)



