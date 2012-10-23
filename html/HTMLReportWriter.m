classdef HTMLReportWriter < HTMLWriter 

    properties
        reportHeader = 'report.header.html';
        reportFooter = 'report.footer.html';

        pageTitle = 'Report';
        mainHeader = 'Report'; 
        subHeader = '';
        navTitle = '';
        navSubTitle = '';
        timestamp = '';
    end

    methods
        function html = HTMLReportWriter(varargin)
            html = html@HTMLWriter(varargin{:});

            % set timestamp to now
            html.timestamp = datestr(now, 'ddd dd mmm yyyy HH:MM:SS');
        end

        function writeHeader(html, varargin)
            writeHeader@HTMLWriter(html, varargin{:});

            opts.pageTitle = html.pageTitle;
            opts.mainHeader = html.mainHeader;
            opts.subHeader = html.subHeader;
            opts.navTitle = html.navTitle;
            opts.navSubTitle = html.navSubTitle;
            opts.timestamp = html.timestamp;

            html.writeTemplateFile(html.reportHeader, opts, varargin{:});
        end

        function writeFooter(html, varargin)
            opts.timestamp = html.timestamp;
            html.writeTemplateFile(html.reportFooter, opts, varargin{:});

            writeFooter@HTMLWriter(html, varargin{:});
        end


    end
end
        
