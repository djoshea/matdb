%testDatabase

table = c;
html = HTMLDataTableWriter();
html.generate(table);
html.openInBrowser();
