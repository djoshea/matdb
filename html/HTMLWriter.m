classdef HTMLWriter < handle

    properties
        fid
        fileName

        templateHeader= 'writer.header.html';
        templateFooter = 'writer.footer.html';

        % actual location of resources
        resourcesPath = '';

        % if in the middle of a string literal, don't insert unnecessary newlines
        inString = false;
    end

    properties(Dependent)
        resourcesPathStore
        resourcesRelativeUrl
        basePath
    end

    
    methods(Static)
        function openFileInBrowser(fileName)
            if ismac
                cmd = sprintf('open "%s"', fileName);
                system(cmd);
            elseif isunix
                cmd = sprintf('export LD_LIBRARY_PATH=/usr/lib/firefox && export DISPLAY=:0.0 && firefox "%s"', fileName);
                unix(cmd);
            else
                winopen(fileName);
            end
        end
    end
    
    methods
        function openInBrowser(html)
            if isa(html, 'HTMLWriter')
                fileName = GetFullPath(html.fileName);
            else
                fileName = GetFullPath(html);
            end
            
            HTMLWriter.openFileInBrowser(fileName);
        end
    end

    methods
        function html = HTMLWriter(fileName)
            if nargin == 1
                html.fileName = fileName;
            end

            % resources live in the folder where I am
            html.resourcesPath = GetFullPath(fullfile(pathToThisFile(), 'resources'));
        end
        
        % location of resources that should be referenced from the html file
        % resources will be copied to this location 
        function path = get.resourcesPathStore(html)
            path = fullfile(html.basePath, 'resources');
        end

        function url = get.resourcesRelativeUrl(html)
            url = html.getRelativeUrl(html.resourcesPathStore);
        end

        function base = get.basePath(html)
            base = GetFullPath(fileparts(html.fileName));
        end

        function relPath = getRelativePath(html, fileName)
            relPath = relativepath(fileName, html.basePath);
        end

        function relUrl = getRelativeUrl(html, fileName)
            relPath = html.getRelativePath(fileName);
            if strncmp(relPath, './', 2)
                relPath = relPath(3:end);
            end
            relUrl = [relPath];
        end

        function openFile(html)
            if isempty(html.fileName)
                % use a temporary file
                html.fileName = [tempname() '.html'];
            end

            parentDir = fileparts(html.fileName);
            if ~exist(parentDir, 'dir')
                mkdirRecursive(parentDir);
            end
            [html.fid message] = fopen(html.fileName, 'w');
            if html.fid == -1
                error('Error opening html file:\n%s', message);
            end
        end

        function closeFile(html)
            if ~isempty(html.fid)
                fclose(html.fid);
                html.fid = [];
            end
        end

        function success = copyResources(html)
            src = GetFullPath(html.resourcesPath);
            dest = html.resourcesPathStore;

            if ~strcmp(src(end), filesep)
                src = [src filesep];
            end

            cmd = sprintf('cp -R "%s" "%s"', src, dest);
            [status, message] = unix(cmd);
            if status
                fprintf('Warning: issues copying html resources to target directory\n');
                fprintf('%s\n', message);
            end
            success = ~status;
        end

        function [status result] = tidy(html)
            cmd = sprintf('tidy -indent -m %s', html.fileName);
            [status result] = system(cmd);
        end

        function checkOpen(html)
            assert(~isempty(html.fid), 'Call .openFile() before writing');
        end

        function fprintf(html, varargin)
            html.checkOpen();
            fprintf(html.fid, varargin{:});
        end

        function lineBreakIfNotInString(html)
            if ~html.inString
                html.fprintf('\n');
            end
        end

        function writeTemplate(html, text, varargin)
            % writeTemplate(text, 'key1', 'value1', 'key2', 'value2');
            % writeTemplate(text, valueMap)
            %
            % write the contents of filename into the current document
            % substituting valueMap(key) for template variables of the form '{{key}}'

            if isempty(varargin)
                valueMap = containers.Map('KeyType', 'char', 'ValueType', 'char');
            elseif isa(varargin{1}, 'containers.Map')
                valueMap = varargin{1};
            else
                p = inputParser;
                p.KeepUnmatched = true;
                p.parse(varargin{:});
                valueMap = structArrayToMap(p.Unmatched);
            end

            keys = valueMap.keys;
            for i = 1:length(keys)
                key = keys{i};
                value = valueMap(key); 

                % replace {{ key }} with value
                regexPat = ['\{\{\s*' key '\s*\}\}'];
                text = regexprep(text, regexPat, value);
            end

            % replace all other {{   }} with ''
            regexPat = '\{\{\s*\w*\s*\}\}';
            text = regexprep(text, regexPat, '');

            html.fprintf('%s', text);
        end

        function writeTemplateFile(html, filename, varargin)
            % like writeTemplate but the text is read from file filename
            text = fileread(filename);
            html.writeTemplate(text, 'resourcesPath', html.resourcesRelativeUrl, varargin{:});
        end

        function writeFileStub(html, filename)
            % cat file filename into the current file
            text = fileread(filename);
            html.fprintf('%s', text);
        end

        function writeHeader(html, varargin)
            if nargin < 2
                title = '';
            end

            html.writeTemplateFile(html.templateHeader, varargin{:});
        end

        function writeFooter(html)
            html.writeTemplateFile(html.templateFooter);
        end

        function writeH1(html, str)
            html.fprintf('<h1>%s</h1>', str);
        end

        function writeH2(html, str)
            html.fprintf('<h2>%s</h2>', str);
        end

        function openDivRow(html)
            html.fprintf('<div class="row">');
        end

        function closeDivRow(html)
            html.fprintf('</div>');
        end

        function openDivSpan(html, span)
            html.fprintf('<div class="span%d">', span);
        end

        function closeDivSpan(html)
            html.fprintf('</div>');
        end

        function openTag(html, tag, varargin)
            p = inputParser;
            p.KeepUnmatched = true;
            p.parse(varargin{:});
            attr = p.Unmatched;

            % build the attribute name="value" string
            attrList = fieldnames(attr);
            if isempty(attrList)
                attrStr = '';
            else
                if html.inString
                    quote = '''';
                else
                    quote = '"';
                end
                attrCell = cellfun(@(name) sprintf(' %s=%s%s%s', name, quote, attr.(name), quote), attrList, ...
                    'UniformOutput', false);
                attrStr = strjoin(attrCell, '');
            end

            html.fprintf('<%s%s>', tag, attrStr);
            html.lineBreakIfNotInString();
        end

        function closeTag(html, tag)
            html.fprintf('</%s>', tag);
            html.lineBreakIfNotInString();
        end

        function writeTag(html, tag, contents, varargin)
            html.openTag(tag, varargin{:});
            html.fprintf('%s', contents);
            html.closeTag(tag);
        end
        
        function openTable(html, varargin)
            html.openTag('table', 'class', 'table', varargin{:});
        end

        function closeTable(html)
            html.closeTag('table');
        end

        function openTableHead(html, varargin)
            html.openTag('thead', varargin{:});
        end

        function closeTableHead(html)
            html.closeTag('thead');
        end

        function openTableBody(html)
            html.openTag('tbody');
        end

        function closeTableBody(html)
            html.closeTag('tbody');
        end

        function openTableRow(html, varargin)
            html.openTag('tr', varargin{:});
        end

        function closeTableRow(html)
            html.closeTag('tr');
        end

        function openTableHeaderCell(html)
            html.openTag('th');
        end

        function closeTableHeaderCell(html)
            html.closeTag('th');
        end

        function openTableCell(html, varargin)
            html.openTag('td', varargin{:});
        end

        function closeTableCell(html)
            html.closeTag('td');
        end

        function writeStructArrayAsTable(html, S, fieldExtrasMap)
            assert(isstruct(S));
            if nargin < 3
                fieldExtrasMap = containers.Map('KeyType', 'char', 'ValueType', 'any');
            end

            html.openDivRow();
            html.openDivSpan(12);

            html.openTable('class', 'table table-condensed table-hover table-bordered');

            % write fields in header
            html.openTableHead();
            html.openTableRow();
            fields = fieldnames(S);
            nFields = length(fields);

            for i = 1:nFields
                field = fields{i};
                if fieldExtrasMap.isKey(field)
                    extras = fieldExtrasMap(field);
                    if ~iscell(extras)
                        extras = {extras};
                    end
                else
                    extras = {};
                end
                html.writeTag('th', field, extras{:});
            end
            html.closeTableRow();
            html.closeTableHead();
            
            % write entry rows
            html.openTableBody();
            nEntries = length(S); 
            for iEntry = 1:nEntries
                html.openTableRow();
                entry = S(iEntry);

                for iField = 1:nFields
                    field = fields{iField};
                    if fieldExtrasMap.isKey(field)
                        extras = fieldExtrasMap(field);
                        if ~iscell(extras)
                            extras = {extras};
                        end
                    else
                        extras = {};
                    end
                    html.openTableCell(extras{:});
                    html.writeTag('div', entry.(field), 'class', 'ellipsis'); 
                    html.closeTableCell();
                end

                html.closeTableRow();
            end

            html.closeTableBody();
            html.closeTable();
            html.closeDivSpan();
            html.closeDivRow();
        end

    end
end
        
