import Foundation

@main struct ContentTests {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1]); let bundle = Bundle(path: CommandLine.arguments[2])!
        let fm = FileManager.default;try fm.createDirectory(at:root.appendingPathComponent("nested/deep"),withIntermediateDirectories:true)
        try Data(repeating:65,count:4096).write(to:root.appendingPathComponent("nested/deep/item.dat"))
        var checks:[String:Bool]=[:]
        func check(_ name:String,_ value:Bool){checks[name]=value;print("\(value ? "PASS" : "FAIL") \(name)")}
        check("integerOverflowSaturates",FolderAnalyzer.addingBytes(Int64.max,1).value == Int64.max && FolderAnalyzer.addingBytes(Int64.max,1).overflow)
        let s=FolderAnalyzer.scan(root:root,options:FolderAnalysisOptions(),cancellation:AnalysisCancellation())
        check("folderRecursiveSizes",s.largestLogicalFolders.first{$0.relativePath=="nested"}?.logicalBytes==4096 && s.largestLogicalFolders.first{$0.relativePath=="nested/deep"}?.logicalBytes==4096)
        check("folderOverlapNotAddedToTotal",s.logicalBytes==4096 && s.fileCount==1)
        let decoded=try JSONSerialization.jsonObject(with:Data(s.jsonSummary().utf8)) as! [String:Any]
        check("jsonRoundTrip",decoded["schemaVersion"] as? Int == 1 && (decoded["totals"] as? [String:Any])?["files"] as? Int == 1)
        var unsafe=s;unsafe.issues=[AnalysisIssue(path:"=1+1,\"\n",message:"@formula")]
        check("csvEscapesAndNeutralizesFormula",unsafe.csvSummary().contains("\"'=1+1,\"\"\n\"") && unsafe.csvSummary().contains("'@formula"))
        var limited=FolderAnalysisOptions();limited.maximumEntries=2
        let partial=FolderAnalyzer.scan(root:root,options:limited,cancellation:AnalysisCancellation())
        check("unfinishedFoldersMarkedPartial",partial.isPartial && partial.largestLogicalFolders.allSatisfy(\.partial))
        let code="""
        # Guide
        ## Repeat
        ## Repeat
        ```swift
        let x = "<script>alert(1)</script>"
        // comment
        ```
        | A | B |
        |---|---|
        | 1 | 2 |
        [bad](javascript:alert(1))
        <iframe src="file:///etc/passwd"></iframe>
        <img src="https://example.com/a" onerror="alert(1)">
        [remote](https://example.com)
        __BODY__ __CSS__ __NONCE__ __LIBRARIES__ __PAYLOAD__ __RENDERER__
        """
        let body=try MarkdownDocument.renderBody(source:code,bundle:bundle)
        let html=try MarkdownDocument.quickLookHTML(source:code,bundle:bundle)
        let interactive=try MarkdownDocument.html(source:code,bundle:bundle)
        check("staticHighlightEscapesCode",body.contains("tok-keyword") && body.contains("tok-string") && body.contains("&lt;script&gt;") && !body.contains("<script>"))
        check("tocUniqueAnchors",body.contains("id=\"pk-repeat\"") && body.contains("id=\"pk-repeat-1\"") && body.contains("href=\"#pk-repeat-1\""))
        check("tableFormatting",body.contains("<table>") && body.contains("<td>1</td>"))
        check("staticNoExecutableDocumentHTML",!body.contains("<iframe") && !body.contains("<img src=\"https:") && !body.contains("href=\"javascript:"))
        check("quickLookScriptlessCSP",html.contains("default-src 'none'") && !html.contains("<script"))
        check("interactiveSharesStaticBody",interactive.contains(body))
        check("templateMarkersRemainLiteral",interactive.contains("__BODY__ __CSS__ __NONCE__ __LIBRARIES__ __PAYLOAD__ __RENDERER__"))
        let unknown=try MarkdownDocument.renderBody(source:"```unknown\n<img src=x onerror=alert(1)>\n```",bundle:bundle)
        check("unknownLanguageEscaped",unknown.contains("&lt;img") && !unknown.contains("<img"))
        let large=try MarkdownDocument.renderBody(source:"```swift\n"+String(repeating:"x",count:70_000)+"\n```",bundle:bundle)
        check("highlightSizeBound",!large.contains("tok-"))
        let empty=try MarkdownDocument.quickLookHTML(source:"",bundle:bundle);check("emptyMarkdownState",empty.contains("This Markdown file is empty"))
        let invalid=root.appendingPathComponent("invalid.md");try Data([0xff,0xff]).write(to:invalid)
        do{_=try MarkdownDocument.read(invalid);check("invalidEncodingRejected",false)}catch{check("invalidEncodingRejected",true)}
        let over=root.appendingPathComponent("oversize.md");try Data(repeating:65,count:MarkdownDocument.maximumBytes+1).write(to:over)
        do{_=try MarkdownDocument.read(over);check("oversizeRejected",false)}catch{check("oversizeRejected",true)}
        let token=AnalysisCancellation();let before=(try fm.contentsOfDirectory(atPath:"/dev/fd")).count
        for _ in 0..<10 {let options=FolderAnalysisOptions(maximumEntries:1);_=FolderAnalyzer.scan(root:root,options:options,cancellation:token)}
        check("partialScanClosesDescriptors",(try fm.contentsOfDirectory(atPath:"/dev/fd")).count <= before+1)
        let report:[String:Any]=["passed":checks.values.allSatisfy{$0},"checks":checks]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[3]))
        if !checks.values.allSatisfy({$0}){exit(1)}
    }
}
