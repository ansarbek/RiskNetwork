# Copyright 2015 Paul Govan

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

# http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

library(bnlearn)
library(lattice)
library(networkD3)
library(rhandsontable)
library(d3heatmap)

# By default, the file size limit is 5MB. It can be changed by
# setting this option. Here we'll raise limit to 9MB.
options(shiny.maxRequestSize = 10*1024^2)

# Define required server logic
shinyServer(function(input, output, session) {
  
  # Get data
  data <- reactive({
    if (input$net == 1) {
      data <- learning.test
    } else if (input$net == 2) {
      data <- gaussian.test
    } else if (input$net == 3) {
      data <- insurance
    } else if (input$net == 4) {
      data <- matrix(NA, ncol = 14)
      colnames(data) <- c("Cause-Delays on other project", "Cause-Install scheduled during hurricane season", "Risk-vessel delayed on other project", "Risk-Inclement weather", "Resource-Transport vessel rate", "Resource-2 transport vessels", "Resource-1 install vessel", "Resource-Install vessel rate", "Resource-25 HUC personnel", "Resource-HUC personnel rate", "Task-Jacket, topsides, pile tow", "Task-Offshore install", "Task-HUC", "Project-Platform install")
      data
    } else  {  
      # Get uploaded file
      inFile <- input$file
      if (is.null(inFile))
        return(NULL)
      data <- read.csv(inFile$datapath, header = input$header,
                       sep = input$sep)
    }
  })  
  
  # Learn the structure of the network
  dag <- reactive({
    if (is.null(data()))
      return(NULL)
    if (input$net == 4) {
      dag <- model2network("[Cause-Delays on other project][Cause-Install scheduled during hurricane season][Risk-vessel delayed on other project|Cause-Delays on other project][Risk-Inclement weather|Cause-Install scheduled during hurricane season][Resource-Transport vessel rate][Resource-2 transport vessels|Risk-Inclement weather][Resource-1 install vessel|Risk-Inclement weather][Resource-Install vessel rate|Risk-vessel delayed on other project][Resource-25 HUC personnel][Resource-HUC personnel rate][Task-Jacket, topsides, pile tow|Resource-Transport vessel rate:Resource-2 transport vessels][Task-Offshore install|Resource-Transport vessel rate:Resource-2 transport vessels:Resource-Install vessel rate:Resource-1 install vessel][Task-HUC|Resource-HUC personnel rate:Resource-25 HUC personnel][Project-Platform install|Task-Jacket, topsides, pile tow:Task-Offshore install:Task-HUC]")
      } else if (input$alg == "gs") {
      dag <- cextend(gs(data()), strict=FALSE)
    } else if (input$alg == "iamb") {
      dag <- cextend(iamb(data()), strict=FALSE)
    } else if (input$alg == "fast.iamb") {
      dag <- cextend(fast.iamb(data()), strict=FALSE)
    } else if (input$alg == "inter.iamb") {
      dag <- cextend(inter.iamb(data()), strict=FALSE)
    } else if (input$alg == "hc") {
      dag <- cextend(hc(data()), strict=FALSE)
    } else if (input$alg == "tamu") {
      dag <- cextend(tamu(data()), strict=FALSE)
    } else if (input$alg == "mmhc") {
      dag <- cextend(mmhc(data()), strict=FALSE)
    } else if (input$alg == "rsmax2") {
      dag <- cextend(rsmax2(data()), strict=FALSE)
    } else if (input$alg == "mmpc") {
      dag <- cextend(mmpc(data()), strict=FALSE)
    } else if (input$alg == "si.hiton.pc") {
      dag <- cextend(si.hiton.pc(data()), strict=FALSE)
    } else if (input$alg == "aracne") {
      dag <- cextend(aracne(data()), strict=FALSE)
    } else 
      dag <- cextend(chow.liu(data()), strict=FALSE)
  })
  
  # Create the nodes box
  output$nodesBox <- renderUI({
    if (is.null(data()))
      return(NULL)
    nodes <- nnodes(dag())
    valueBox(nodes, "Nodes", icon = icon("circle"), color = "blue")
  })
  
  # Create the arcs box
  output$arcsBox <- renderUI({
    if (is.null(data()))
      return(NULL)
    arcs <- narcs(dag())
    valueBox(arcs, "Arcs", icon = icon("arrow-right"), color = "green")
  })
  
  # Plot the force directed network
  output$netPlot <- renderSimpleNetwork({
    if (is.null(data()))
      return(NULL)
    networkData <- data.frame(arcs(dag()))
    simpleNetwork(networkData, Source = "from", Target = "to",
                  linkDistance = 100, charge = -400, fontSize = 12, 
                  opacity = 0.8)
  })
  
  # Print the network score
  output$score <- renderText({
    if (is.null(data()) | input$net == 4)
      return(NULL)
    if (directed(dag())) {
      if (is.numeric(data()[,1])) {
        if (input$type == "loglik") {
          score(dag(), data(), type="loglik-g")
        } else if (input$type == "aic") {
          score(dag(), data(), type="aic-g")
        } else if (input$type == "bic") {
          score(dag(), data(), type="bic-g")
        } else {
          score(dag(), data(), type="bge")
        }
      }
      else {
        if (input$type == "loglik") {
          score(dag(), data(), type="loglik")
        } else if (input$type == "aic") {
          score(dag(), data(), type="aic")
        } else if (input$type == "bic") {
          score(dag(), data(), type="bic")
        } else {
          score(dag(), data(), type="bde")
        }
      }
    } else
      validate(
        need(try(score != ""), "Make sure your network is completely directed in order to view your network's score...")
      )
  })
  
  # Fit the model parameters
  fit <- reactive({
    if (is.null(data()))
      return(NULL)
    if (input$net == 4) {
      tf <- c("True", "False")
      cptC1 <- matrix(c(0.75, 0.25), ncol=2, dimnames=list(NULL, tf))
      cptC2 <- matrix(c(0.5, 0.5), ncol=2, dimnames=list(NULL, tf))
      cptR1 <- matrix(c(0.95, 0.05, 0.25, 0.75), 
                      ncol=2, dimnames=list("Risk-vessel delayed on other project"=tf, "Cause-Delays on other project"=tf))
      cptR2 <- matrix(c(0.75, 0.25, 0.4, 0.6), 
                      ncol=2, dimnames=list("Risk-Inclement weather"=tf, "Cause-Install scheduled during hurricane season"=tf))
      lh <- c("Low", "High")
      cptQ1 <- matrix(c(0.1, 0.9, 0.5, 0.5), 
                      ncol=2, dimnames=list("Resource-2 transport vessels"=lh, "Risk-Inclement weather"=tf))
      cptU1 <- matrix(c(0.5, 0.5), 
                      ncol=2, dimnames=list(NULL, lh))
      cptQ2 <- matrix(c(0.1, 0.9, 0.5, 0.5), 
                      ncol=2, dimnames=list("Resource-1 install vessel"=lh, "Risk-Inclement weather"=tf))
      cptU2 <- matrix(c(0.1, 0.9, 0.8, 0.2), 
                      ncol=2, dimnames=list("Resource-Install vessel rate"=lh, "Risk-vessel delayed on other project"=tf))
      cptQ3 <- matrix(c(0.7, 0.3), 
                      ncol=2, dimnames=list(NULL, lh))
      cptU3 <- matrix(c(0.3, 0.7), 
                      ncol=2, dimnames=list(NULL, lh))
      cptT1 <- c(1.0, 0.0, 0.5, 0.5, 0.5, 0.5, 0.0, 1.0)
      dim(cptT1) <- c(2, 2, 2)
      dimnames(cptT1) <- list("Task-Jacket, topsides, pile tow"=lh, "Resource-2 transport vessels"=lh, "Resource-Transport vessel rate"=lh)
      cptT2 <- c(1.0, 0.0, 0.75, 0.25, 0.75, 0.25, 0.5, 0.5, 0.75, 0.25, 0.5, 0.5, 0.5, 0.5, 0.25, 0.75, 0.75, 0.25, 0.5, 0.5, 0.5, 0.5, 0.25, 0.75, 0.5, 0.5, 0.25, 0.75, 0.25, 0.75, 0.0, 1.0)
      dim(cptT2) <- c(2, 2, 2, 2, 2)
      dimnames(cptT2) <- list("Task-Offshore install"=lh, "Resource-2 transport vessels"=lh, "Resource-Transport vessel rate"=lh, "Resource-1 install vessel"=lh, "Resource-Install vessel rate"=lh)
      cptT3 <- c(1.0, 0.0, 1.0, 0.0, 0.5, 0.5, 0.0, 1.0)
      dim(cptT3) <- c(2, 2, 2)
      dimnames(cptT3) <- list("Task-HUC"=lh, "Resource-25 HUC personnel"=lh, "Resource-HUC personnel rate"=lh)
      cptP <- c(1.0, 0.0, 0.67, 0.33, 0.67, 0.33, 0.33, 0.67, 0.67, 0.33, 0.33, 0.67, 0.33, 0.67, 0.0, 1.0)
      dim(cptP) <- c(2, 2, 2, 2)
      dimnames(cptP) <- list("Project-Platform install"=lh, "Task-Jacket, topsides, pile tow"=lh, "Task-Offshore install"=lh, "Task-HUC"=lh)
      fit <- custom.fit(dag(), dist=list("Cause-Delays on other project"=cptC1, "Cause-Install scheduled during hurricane season"=cptC2, "Risk-vessel delayed on other project"=cptR1, "Risk-Inclement weather"=cptR2, 
                                         "Resource-2 transport vessels"=cptQ1, "Resource-Transport vessel rate"=cptU1, "Resource-1 install vessel"=cptQ2, "Resource-Install vessel rate"=cptU2,
                                         "Resource-25 HUC personnel"=cptQ3, "Resource-HUC personnel rate"=cptU3,"Task-Jacket, topsides, pile tow"=cptT1, "Task-Offshore install"=cptT2,
                                         "Task-HUC"=cptT3, "Project-Platform install"=cptP))
    } else if (directed(dag())) {
      fit <- bn.fit(dag(), data(), method = input$met)
    }
  })
  
  # Create data frame for selected paramater
  param <- reactive({
    param <- data.frame(coef(fit()[[input$Node]]))
    if (is.numeric(data()[,1])) {
      colnames(param) <- "Param"
      param <- cbind(param = rownames(param), param)
      param[,"Param"] <- round(param[,"Param"], digits = 3)
      param <- transform(param, Param = as.numeric(Param))
    } else {
      param[,"Freq"] <- round(param[,"Freq"], digits = 3)
      param <- transform(param, Freq = as.numeric(Freq))
    }
  })
  
  # Plot Handsontable for selected parameter
  values = reactiveValues()
  setHot = function(x) values[["hot"]] <<- x
  output$hot = renderRHandsontable({
    if (!is.null(input$hot)) {
      DF = hot_to_r(input$hot)
    } else {
      DF = param()
    }
    if (is.numeric(data()[,1])) {
      col <- "Param"
    } else {
      col <- "Freq"
    }
    setHot(DF)
    rhandsontable(DF, readOnly = TRUE, rowHeaders = NULL) %>%
      hot_table(highlightCol = TRUE, highlightRow = TRUE) %>%
      hot_context_menu(allowRowEdit = FALSE, allowColEdit = FALSE) %>%
      hot_col(col, readOnly = FALSE)
  })
  
  # Add expert knowledge to the model
  expertFit <- reactive({
      if (!is.null(values[["hot"]])) {
        expertFit <- fit()
        temp <- data.frame(values[["hot"]])
        if (is.numeric(data()[,1])) {
          stdev <- as.numeric(fit()[[input$Node]]["sd"])
          expertFit[[input$Node]] <- list(coef = as.numeric(temp[,"Param"]), sd = stdev)
        } else {
          cpt <- coef(expertFit()[[input$Node]])
          cpt[1:length(param()[,"Freq"])] <- as.numeric(temp[,"Freq"])
          expertFit[[input$Node]] <- cpt
        }
      } else {
        expertFit <- fit()
      }
    })
  
  # Set the paramater graphic options
  graphic <- reactive({
    if (is.numeric(data()[,1])) {
      graphic <- c("Histogram"="histogram",
                   "XY Plot"="xyplot",
                   "QQ Plot"="qqplot")
    } else {
      graphic <- c("Bar Chart"="barchart",
                   "Dot Plot"="dotplot")
    }
  })
  
  observe({
    updateSelectInput(session, "param", choices = graphic())
  })
  observe({
    updateSelectInput(session, "Node", choices = colnames(data()))
  })
  
  # Plot the model parameters
  output$condPlot <- renderPlot({
    if (is.null(data()))
      return(NULL)
    if (directed(dag())) {
      if (input$param == "histogram") {
        bn.fit.histogram(fit())
      } else if (input$param == "xyplot") {
        bn.fit.xyplot(fit())
      } else if (input$param == "qqplot") {
        bn.fit.qqplot(fit())
      } else if (input$param == "barchart") {
        bn.fit.barchart(fit()[[input$Node]])
      } else if (input$param == "dotplot") {
        bn.fit.dotplot(fit()[[input$Node]])
      }
    } else
      validate(
        need(try(condPlot != ""), "Make sure your network is completely directed in order to view the paramater infographics...")
      )
  })
  
  observe({
    updateSelectInput(session, "evidence", choices = names(data()))
  })
  
  observe({
    updateSelectInput(session, "event", choices = names(data()))
  })
  
  #   # Perform Bayesian Inference based on evidence and print results
  #   output$distPrint <- renderPrint({
  #     if (is.null(data()))
  #       return(NULL)
  #     if (directed(dag())) {
  #       fitted = fit()
  #       evidence = as.vector(input$evidence)
  #       value = as.vector(input$val)
  #       node.dist <- cpdist(fitted, input$event, eval(parse(text = paste("(", evidence, "=='",
  #                                                                        sapply(value, as.numeric), "')",
  #                                                                        sep = "", collapse = " & "))), method = input$inf)
  #     } else
  #       validate(
  #         need(try(distPlot != ""), "Make sure your network is completely directed in order to perform Bayesian inference...")
  #       )
  #   })
  
  observe({
    updateSelectInput(session, "nodeNames", choices = colnames(data()))
  })
  
  # Show node measures
  output$nodeText <- renderText({
    if (is.null(data()))
      return(NULL)    
    if (input$nodeMeasure == "mb") {
      mb(dag(), input$nodeNames)
    } else if (input$nodeMeasure == "nbr") {
      nbr(dag(), input$nodeNames)
    } else if (input$nodeMeasure == "parents") {
      parents(dag(), input$nodeNames)
    } else if (input$nodeMeasure == "children") { 
      children(dag(), input$nodeNames)
    } else if (input$nodeMeasure == "in.degree") { 
      in.degree(dag(), input$nodeNames)
    } else if (input$nodeMeasure == "out.degree") { 
      out.degree(dag(), input$nodeNames)
    } else if (input$nodeMeasure == "incident.arcs") { 
      incident.arcs(dag(), input$nodeNames)
    } else if (input$nodeMeasure == "incoming.arcs") {
      incoming.arcs(dag(), input$nodeNames)
    } else if (input$nodeMeasure == "outgoing.arcs") {
      outgoing.arcs(dag(), input$nodeNames)
    } else
      incident.arcs(dag(), input$nodeNames)
  })
  
  # Show network measures
  output$netTable <- renderD3heatmap({
    if (is.null(data()))
      return(NULL)
      d3heatmap(amat(dag()), dendrogram = input$dendrogram, symm = TRUE, 
                cexRow = 0.7, cexCol = 0.7, colors = "Blues")
  })
  
  simData <- reactive({
    simData <- rbn(fit(), input$n)
  })
  
  output$downloadData <- downloadHandler(
    filename = function() { 
      paste('bn', '.csv', sep='') 
    },
    content = function(file) {
      write.csv(simData(), file)
    }
  )
})
