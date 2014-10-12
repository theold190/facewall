View = require './view'

class FaceWallView extends View

    columnWidth: constants.columnWidth

    useAutoSizing: constants.useAutoSizing
    useAutoSizingNextTime: constants.useAutoSizing

    paused: not constants.autoplay

    threedee: constants.threedee

    template: require './templates/facewall'

    cache_bust_image_counter: 0

    initialize: =>
        @zindex = 200
        view = @

        @collection = app.collections.employees

        $(window).resize ->
            if app.views.current_view is view and ((view.last_rendered_width isnt $(window).width()) or (view.useAutoSizing is true))
                view.useAutoSizingNextTime = true if view.useAutoSizing
                $('#loader').show()
                view.render()

        setInterval ->
            if app.views.current_view is view and not view.paused
                view.featureRandomEmployee()
        , (1000 * constants.autoplay_seconds)

    render: =>
        view = @

        @last_rendered_width = $(window).width()

        return unless @collection.toJSON().length

        window.document.body.style.cssText = "opacity: 0; background: #{constants.styles.background}"

        $(@el).html @template

        @resetRefreshedTimeout()

        @setThreeDee()

        # Part of the FOAC hack (above)
        setTimeout (-> window.document.body.style.cssText = "opacity: 1; background: #{constants.styles.background}"), 500

        $fw = $(@el).find('.facewall')

        $employee = (employee, height, width) -> """
            <a data-email="#{employee.email}" class="employee facewall-flyin" style="width: #{width}px; height: #{height}px;">
                <span class="name">#{employee.firstName.substr(0, 1) + employee.lastName.substr(0, 1)}</span>
                <img class="photo" src="#{view.getThumbnailUrl(employee)}" />
            </a>
        """

        employees = _.shuffle app.collections.employees.toJSON()

        @grid = grid = @getGrid @columnWidth

        badBucket = []
        goodBucket = []

        _.each employees, (employee) ->
            employee_img = new Image()

            employee_img.onload = ->
                goodBucket.push employee
                employee_loaded()

            employee_img.onerror = ->
                badBucket.push employee
                employee_loaded()

            employee_img.src = view.getThumbnailUrl(employee)

        employees_loaded = 0

        writeEmployeeRow = (row_bucket, row_count) =>
            $row = $ """
                <div class="employee-row"></div>
            """
            $fw.append $row

            _.each row_bucket, (employee_in_row, index) ->
                width = grid[index]

                setTimeout ->
                    $('#loader').hide() is index is 0
                    $row.append $employee(employee_in_row, grid[0], width)

                , (((row_count * grid.length) + index) * 30)

        employee_loaded = =>
            employees_loaded += 1

            if employees_loaded is employees.length
                row_bucket = []
                row_count = 0

                if @useAutoSizingNextTime and goodBucket.length > 0
                    @useAutoSizingNextTime = false
                    @columnWidth = @getOptimumGridColumnWidth @getOptions(), goodBucket.length
                    view.render()

                _.each goodBucket, (employee) ->
                    if row_bucket.length is grid.length
                        writeEmployeeRow row_bucket, row_count
                        row_bucket = []
                        row_count += 1

                    row_bucket.push employee

                if row_bucket.length > 0
                    writeEmployeeRow row_bucket, row_count

                return

        $fw.undelegate('a.employee', 'click').delegate 'a.employee', 'click', (e) =>
            view.paused = true
            @resetRefreshedTimeout()
            $e = $(e.target)
            $e = $e.parents('a.employee') if $e.parents('a.employee').length
            if $e.hasClass('featured-employee')
                @unfeatureEmployee()
            else
                @featureEmployee $e

        @setupKeyboardEvents()

    featureRandomEmployee: (attempts = 0) =>
        attempts += 1
        return if attempts > 100

        employee = _.first _.shuffle @collection.toJSON()

        return @featureRandomEmployee attempts unless $(@el).find("a.employee[data-email='#{employee.email}']").length

        @search = ''
        @updateSearchDisplay()

        @unfeatureEmployee()

        @featureEmployee employee.email

    featureEmployee: (string_or_$target) =>
        view = @

        if typeof string_or_$target is 'string'
            email = string_or_$target
        else
            email = string_or_$target.data('email')

        return unless email

        employee = (@collection.find (employee) -> employee.get('email') is email).toJSON()
        return unless employee

        $fw = $(@el).find('.facewall')

        # Return if already featured
        return if $fw.find("a.featured-employee[data-email='#{email}']").length

        @unfeatureEmployee()

        view.zindex -= 1
        $fw.find("a.employee[data-email='#{email}']").addClass('featured').css zIndex: view.zindex

        @flyToFeatured() if @threedee

        employee_img = new Image()
        view.zindex += 3
        employee_img.onload = ->
            $fw.find("a.featured-employee").fadeOut('fast', -> $(@).remove())

            $fw.append """
                <a data-email="#{employee.email}" class="employee featured featured-employee facewall-featureEmployee-and-flipInY" style="z-index: #{view.zindex}">
                    <span class="name">#{employee.firstName}</span>
                    <span class="role">#{employee.role}</span>
                    <img class="photo" src="#{view.getFullImageUrl(employee)}"" />
                </a>
            """
        employee_img.onerror = ->
            view.unfeatureEmployee()

        employee_img.src = "#{view.getFullImageUrl(employee)}"

    unfeatureEmployee: =>
        $fw = $(@el).find('.facewall')

        $fw.find('.featured-employee').fadeOut('fast', -> $(@).remove())
        $fw.find('a.employee.featured:not(".featured-employee")').removeClass('featured')

    resetRefreshedTimeout: =>
        view = @
        clearTimeout(@lastTouchTimeout) if @lastTouchTimeout

        @lastTouchTimeout = setTimeout ->
            view.cache_bust_image_counter++
            view.render()
        , (1000 * constants.refresh_seconds)

    setupKeyboardEvents: =>
        view = @

        @search = ''

        $fw = $(@el).find('.facewall')

        $(window).unbind('keydown.facewall').bind 'keydown.facewall', (e) =>
            return unless app.views.current_view is view
            return if view.suspend_keyboard

            view.paused = true
            @resetRefreshedTimeout()

            $featured = $fw.find('.featured:not(".featured-employee")')

            if e.keyCode is 27 # escape
                @unfeatureEmployee() if @search is ''
                @search = ''
                view.updateSearchDisplay()
                e.preventDefault()

            if e.keyCode is 32 and @search is ''
                return @paused = not @paused

            if e.keyCode is 51
                @search = ''
                @threedee = not @threedee
                return @setThreeDee()

            # Search (letters or space or backspace or period or apostophe)
            if 65 <= e.keyCode <= 90 or e.keyCode is 32 or e.keyCode is 8 or e.keyCode is 222 or e.keyCode is 190
                new_search = @search

                if e.keyCode is 8
                    new_search = new_search.substr(0, new_search.length - 1)

                else if e.keyCode is 222
                    new_search += "'"

                else
                    new_search += String.fromCharCode(e.keyCode).toLowerCase()

                if new_search.length > 1
                    employee_matches = @collection.filter((e) -> (new RegExp(new_search.toLowerCase())).test((e.get('firstName') + ' ' + e.get('lastName')).toLowerCase()))
                    if employee_matches.length > 0
                        @paused = true
                        for employee_match in employee_matches
                            $employee_match = $fw.find("a.employee[data-email='#{employee_match.get('email')}']")
                            if $employee_match.length
                                @search = new_search
                                @featureEmployee employee_match.get('email')
                                if employee_matches.length is 1 and e.keyCode isnt 8
                                    @search = (employee_match.get('firstName') + ' ' + employee_match.get('lastName')).toLowerCase()
                                break

                else
                    @search = new_search

                view.updateSearchDisplay()

                return false

            unless $featured.length
                @featureEmployee $fw.find('.employee').first()

            # Navigation and Settings

            $naved_employee = false

            switch e.keyCode
                when 37 # left
                    if $featured.index() > 0
                        $naved_employee = $featured.prev('.employee')
                    else
                        $naved_employee = $featured.parent().prev('.employee-row').find('.employee').last()

                when 39 # right
                    if $featured.index() < @grid.length - 1
                        $naved_employee = $featured.next('.employee')
                    else
                        $naved_employee = $featured.parent().next('.employee-row').find('.employee').first()

                when 38 # up
                    $naved_employee = $featured.parent().prev('.employee-row').find('.employee').eq($featured.index())

                when 40 # down
                    $naved_employee = $featured.parent().next('.employee-row').find('.employee').eq($featured.index())

                when 189, 187 # -, +
                    direction = if e.keyCode is 189 then -1 else 1
                    view.columnWidth += direction * 20
                    view.useAutoSizing = false
                    view.useAutoSizingNextTime = false
                    view.render()
                    e.preventDefault()

            if $naved_employee
                @paused = true
                @featureEmployee $naved_employee
                e.preventDefault()

    updateSearchDisplay: =>
        $search = $(@el).find('.facewall-search')

        if @search is ''
            $search.removeClass('facewall-search-opened').removeClass('facewall-flyin')

        else
            # Capitalize names after splitting by space and apostrophe (Yeah CTOD!)
            search = _.map(@search.split(' '), (w) -> _.map(w.split("'"), (p) -> _.capitalize(p)).join("'")).join('&nbsp;')
            $search.addClass('facewall-flyin').addClass('facewall-search-opened').html search

    printLine = (line, text) -> console.log line + " " + text

    getOptions: () ->
        options =
            width: $(window).width()
            height: $(window).height()
            minColumns: 3
            maxColumns: 100
        return options

    getOptimumGridColumnWidth: (options, numPictures) ->
        currentBestSide = 0

        if numPictures < 2
            return options.width

        #Find a rows/columns combination that would give biggest images size
        for numColumns in [options.minColumns...options.maxColumns]
            numLastRow = numPictures % numColumns
            numRows = parseInt(numPictures / numColumns, 10)
            if numLastRow > 0
                numRows += 1

            candidateWidth = parseInt(options.width / numColumns, 10)
            candidateHeight = parseInt(options.height / numRows, 10)

            # Making sure all pictures will fit
            candidateSide = Math.min(candidateWidth, candidateHeight)
            if candidateSide > currentBestSide
                currentBestSide = candidateSide

        return currentBestSide

    getGrid: (columnWidth) ->
        width = $(window).width()
        if columnWidth is 0
            columnWidth = width

        numColumns = parseInt(width / columnWidth, 10)
        return (columnWidth for num in [1..numColumns])

    setThreeDee: =>
        $(@el).find('.facewall')["#{if @threedee then 'add' else 'remove'}Class"]('facewall-threedee')

        if @threedee
            @flyToFeatured()
        else
            @unfeatureEmployee()
            $('.facewall-styles').html ''

    flyToFeatured: =>
        $featured = $(@el).find('.facewall').find('.featured:not(".featured-employee")')
        return unless $featured.length

        row_index = $featured.parent().index()
        column_index = $featured.index()

        translateX = ($(window).width() / 2) - ((column_index + 0.5) * @grid[0])
        translateY = ($(window).height() / 2) - ((row_index + 0.5) * @grid[0])

        $('.facewall-styles').html """
            <style>
                .employee {
                    -webkit-transform: translateX(#{translateX}px) translateY(#{translateY}px) translateZ(100px) !important;
                }
                .employee.featured {
                    -webkit-transform: translateX(#{translateX}px) translateY(#{translateY}px) translateZ(330px) !important;
                }
            </style>
        """

    getThumbnailUrl: (employee) =>
        if employee.thumbnail?
            return "#{employee.thumbnail}"
        else
            return "#{employee.gravatar}&s=#{@grid[0]}&_=#{@cache_bust_image_counter}"

    getFullImageUrl: (employee) =>
        if employee.fullImage?
            return "#{employee.fullImage}"
        else
            return "#{employee.gravatar}&s=600"

module.exports = FaceWallView